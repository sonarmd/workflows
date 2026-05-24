#!/usr/bin/env bash
#
# agent-review — Stage 1 entrypoint for ghcr.io/sonarmd/agent-reviewer
#
# Reads the PR diff + metadata that the prepare job wrote to:
#   /work/diff.patch
#   /work/pr-meta.json   { head_sha, base_sha, pr_number, repo, ... }
#
# Composes the selected rubric + overlays into a SINGLE claude-code call,
# parses the model's JSON output, adds fingerprints + run metadata, and
# writes findings.json (schema v2) to a path the publisher will read.
#
# Required env (one of):
#   CLAUDE_CODE_OAUTH_TOKEN  — subscription auth (preferred, subscription billing)
#   ANTHROPIC_API_KEY        — fallback (per-token API billing)
#
# Other env:
#   AGENT_REVIEWER_INPUT_DIR    (default /work)
#   AGENT_REVIEWER_OUTPUT_PATH  (default /work/findings.json)
#   REVIEW_MODE            (default 'architecture')
#   OVERLAYS               (default 'senior-eye')
#   INCLUDE_PATHS          (newline-separated globs, default '')
#   EXCLUDE_PATHS          (newline-separated globs, default '')
#   MAX_FINDINGS           (default 50)
#   MAX_DIFF_BYTES         (default 200000)
#
# Exit codes:
#   0  — success (findings.json written; may be empty)
#   2  — usage error
#
# On claude failure or malformed output: writes a findings.json with
# parser_status=malformed and exits 0. The publisher handles this case
# without blocking the workflow.
#
# This script never calls the GitHub API. No gh CLI in the image.

set -euo pipefail

INPUT_DIR="${AGENT_REVIEWER_INPUT_DIR:-/work}"
OUTPUT_PATH="${AGENT_REVIEWER_OUTPUT_PATH:-/work/findings.json}"
REVIEW_MODE="${REVIEW_MODE:-architecture}"
OVERLAYS="${OVERLAYS:-senior-eye}"
INCLUDE_PATHS="${INCLUDE_PATHS:-}"
EXCLUDE_PATHS="${EXCLUDE_PATHS:-}"
MAX_FINDINGS="${MAX_FINDINGS:-50}"
MAX_DIFF_BYTES="${MAX_DIFF_BYTES:-200000}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
agent-review — Stage 1 of agent-architecture-review.

Reads PR diff + metadata from $AGENT_REVIEWER_INPUT_DIR.
Emits findings.json conforming to /opt/schemas/findings.v2.schema.json
to $AGENT_REVIEWER_OUTPUT_PATH.

Never talks to GitHub. Never executes PR code.
EOF
  exit 0
fi

require_env() {
  local var="$1"
  if [[ -z "${!var:-}" ]]; then
    echo "::error::missing required env: $var" >&2
    exit 2
  fi
}

if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" && -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "::error::no claude auth — set CLAUDE_CODE_OAUTH_TOKEN (preferred) or ANTHROPIC_API_KEY" >&2
  exit 2
fi
if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
  echo "::notice::auth: CLAUDE_CODE_OAUTH_TOKEN (subscription)"
else
  echo "::notice::auth: ANTHROPIC_API_KEY (per-token)"
fi

DIFF_FILE="$INPUT_DIR/diff.patch"
META_FILE="$INPUT_DIR/pr-meta.json"

for f in "$DIFF_FILE" "$META_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "::error::expected input file missing: $f" >&2
    exit 2
  fi
done

REPO=$(jq -r '.repo' "$META_FILE")
PR_NUMBER=$(jq -r '.pr_number' "$META_FILE")
HEAD_SHA=$(jq -r '.head_sha' "$META_FILE")
BASE_SHA=$(jq -r '.base_sha' "$META_FILE")
PR_TITLE=$(jq -r '.title // ""' "$META_FILE")

DIFF_BYTES=$(wc -c < "$DIFF_FILE" | tr -d ' ')
DIFF_TRUNCATED=false
if [[ "$DIFF_BYTES" -gt "$MAX_DIFF_BYTES" ]]; then
  echo "::warning::diff size ${DIFF_BYTES} exceeds cap ${MAX_DIFF_BYTES}; truncating at file boundary"
  TRUNCATED_FILE="${DIFF_FILE}.truncated"
  # Truncate at `diff --git` block boundaries so we never feed the model
  # a half-hunk that misleads its line numbers. Drop whole files from the
  # tail once we exceed the cap.
  #
  # Exit semantics:
  #   0 = nothing dropped (shouldn't happen here since we already know
  #       we exceed cap, but kept consistent with awk's `exit 0` default)
  #   1 = at least one file dropped (intentional truncation)
  #   * = awk crashed — caller must NOT proceed with this output
  set +e
  awk -v cap="$MAX_DIFF_BYTES" '
    BEGIN { bytes=0; block=""; output=""; truncated=0 }
    function flush(    bw) {
      bw = bytes + length(block)
      if (bw <= cap) { output = output block; bytes = bw }
      else { truncated = 1 }
      block = ""
    }
    /^diff --git / {
      if (NR > 1) flush()
      block = $0 "\n"
      next
    }
    { block = block $0 "\n" }
    END {
      flush()
      printf "%s", output
      exit truncated
    }
  ' "$DIFF_FILE" > "$TRUNCATED_FILE"
  AWK_EXIT=$?
  set -e

  case "$AWK_EXIT" in
    0)  DIFF_TRUNCATED=false ;;
    1)  DIFF_TRUNCATED=true  ;;
    *)
      echo "::error::truncation awk exited with code ${AWK_EXIT} — possible crash"
      emit_malformed "diff truncation step crashed (awk exit ${AWK_EXIT})"
      exit 0
      ;;
  esac

  # Single-file fallback: if every file individually exceeds the cap,
  # the file-boundary truncator produces a 0-byte output (worse than
  # the old head -c behavior). Fall back to byte-truncating the FIRST
  # diff block at a line boundary so the model still gets something.
  if [[ ! -s "$TRUNCATED_FILE" ]]; then
    echo "::warning::no file fit under cap; falling back to byte-truncation of the first file"
    awk -v cap="$MAX_DIFF_BYTES" '
      BEGIN { bytes=0; in_first=0 }
      /^diff --git / { if (in_first) exit; in_first=1; print; bytes += length($0) + 1; next }
      in_first {
        new_bytes = bytes + length($0) + 1
        if (new_bytes > cap) exit
        print
        bytes = new_bytes
      }
    ' "$DIFF_FILE" > "$TRUNCATED_FILE"
    DIFF_TRUNCATED=true
  fi
  DIFF_FILE="$TRUNCATED_FILE"
  if [[ "$DIFF_TRUNCATED" == "true" ]]; then
    echo "::warning::diff truncated — review will be partial"
  fi
fi

# Apply include/exclude path filtering by editing the diff. The diff is a
# sequence of file-blocks starting with `diff --git`; we split, filter,
# and rejoin.
filter_diff_paths() {
  local diff="$1"
  local include="$2"
  local exclude="$3"
  [[ -z "$include" && -z "$exclude" ]] && { cat "$diff"; return; }

  awk -v include="$include" -v exclude="$exclude" '
    function path_matches(path, globs,    n, i, parts, g, re) {
      if (globs == "") return 0
      n = split(globs, parts, "\n")
      for (i = 1; i <= n; i++) {
        g = parts[i]
        if (g == "") continue
        re = g
        gsub(/\./, "\\.", re)
        # Protect with placeholders before expansion so the second gsub
        # does not re-match the output of the first. Without this,
        # `**/foo/**` was translating to `.[^/]*/foo/.[^/]*` (the `.*`
        # produced by `**` was being chewed by the `*` rule).
        gsub(/\*\*/, "\001", re)   # \001 placeholder for **
        gsub(/\*/,   "\002", re)   # \002 placeholder for *
        gsub(/\001/, ".*",    re)  # expand ** to .*
        gsub(/\002/, "[^/]*", re)  # expand * to [^/]*
        gsub(/\?/, ".", re)
        if (path ~ ("^" re "$")) return 1
      }
      return 0
    }
    /^diff --git / {
      if (NR > 1 && keep) printf "%s", block
      block = $0 "\n"
      split($0, f, " ")
      sub(/^b\//, "", f[4])
      cur_path = f[4]
      keep = 1
      if (include != "" && !path_matches(cur_path, include)) keep = 0
      if (exclude != "" &&  path_matches(cur_path, exclude)) keep = 0
      next
    }
    { block = block $0 "\n" }
    END { if (keep) printf "%s", block }
  ' "$diff"
}

FILTERED_DIFF=$(mktemp)
trap 'rm -f "$FILTERED_DIFF"' EXIT
filter_diff_paths "$DIFF_FILE" "$INCLUDE_PATHS" "$EXCLUDE_PATHS" > "$FILTERED_DIFF"

case "$REVIEW_MODE" in
  architecture|architecture+senior|security|compliance|custom) ;;
  *)
    echo "::error::invalid REVIEW_MODE: $REVIEW_MODE" >&2
    exit 2 ;;
esac

KNOWN_OVERLAYS="senior-eye security hipaa-soc2"
IFS=',' read -ra OVERLAY_LIST <<< "$OVERLAYS"
SELECTED_OVERLAYS=()
for raw in "${OVERLAY_LIST[@]}"; do
  o="$(echo "$raw" | tr -d '[:space:]')"
  [[ -z "$o" ]] && continue
  if ! grep -qw "$o" <<< "$KNOWN_OVERLAYS"; then
    echo "::error::unknown overlay: $o (allowed: $KNOWN_OVERLAYS)" >&2
    exit 2
  fi
  SELECTED_OVERLAYS+=("$o")
done

emit_malformed() {
  local reason="$1"
  local overlay_json
  if [[ ${#SELECTED_OVERLAYS[@]} -eq 0 ]]; then
    overlay_json='[]'
  else
    overlay_json=$(printf '%s\n' "${SELECTED_OVERLAYS[@]}" | jq -R . | jq -s .)
  fi
  jq -n \
    --arg head "$HEAD_SHA" \
    --arg base "$BASE_SHA" \
    --arg mode "$REVIEW_MODE" \
    --argjson overlays "$overlay_json" \
    --arg reason "$reason" \
    '{
      schema_version: "2",
      head_sha: $head,
      base_sha: $base,
      review_mode: $mode,
      overlays_applied: $overlays,
      parser_status: "malformed",
      summary_markdown: ("Agent review was unavailable for this PR. Reason: " + $reason),
      labels: [],
      categories_present: [],
      findings: []
    }' > "$OUTPUT_PATH"
}

PROMPT_FILE=$(mktemp)
trap 'rm -f "$FILTERED_DIFF" "$PROMPT_FILE"' EXIT

{
  cat <<EOF
You are reviewing a pull request diff. Output ONLY a single JSON object
conforming to the schema described below. Do not output any prose before
or after the JSON. Do not include markdown fences.

PR metadata:
  repository: ${REPO}
  pr_number:  ${PR_NUMBER}
  title:      ${PR_TITLE}
  base_sha:   ${BASE_SHA}
  head_sha:   ${HEAD_SHA}

Review mode: ${REVIEW_MODE}
Overlays applied: ${SELECTED_OVERLAYS[*]:-(none)}

EOF

  case "$REVIEW_MODE" in
    architecture|architecture+senior|custom)
      echo "## Default rubric — ARCHITECTURE"; echo
      cat "${AGENT_REVIEWER_RUBRICS_DIR}/architecture.md"; echo ;;
    security)
      echo "## Default rubric — SECURITY"; echo
      cat "${AGENT_REVIEWER_RUBRICS_DIR}/security.md"; echo ;;
    compliance)
      echo "## Default rubric — COMPLIANCE (HIPAA/SOC2)"; echo
      cat "${AGENT_REVIEWER_RUBRICS_DIR}/hipaa-soc2.md"; echo ;;
  esac

  for overlay in "${SELECTED_OVERLAYS[@]}"; do
    case "$overlay" in
      senior-eye)
        echo "## Overlay — SENIOR EYE"; echo
        cat "${AGENT_REVIEWER_RUBRICS_DIR}/senior-eye.md"; echo ;;
      security)
        if [[ "$REVIEW_MODE" != "security" ]]; then
          echo "## Overlay — SECURITY"; echo
          cat "${AGENT_REVIEWER_RUBRICS_DIR}/security.md"; echo
        fi ;;
      hipaa-soc2)
        if [[ "$REVIEW_MODE" != "compliance" ]]; then
          echo "## Overlay — HIPAA/SOC2"; echo
          cat "${AGENT_REVIEWER_RUBRICS_DIR}/hipaa-soc2.md"; echo
        fi ;;
    esac
  done

  cat <<EOF
## Output schema

Emit EXACTLY one JSON object matching this shape. Maximum ${MAX_FINDINGS} findings.

\`\`\`
{
  "schema_version": "2",
  "summary_markdown": "<one-paragraph TL;DR for humans; up to 6 sentences>",
  "labels": ["agent-review/<kebab>"],
  "categories_present": ["architecture", ...],
  "findings": [
    {
      "severity": "critical|high|medium|low|info",
      "confidence": "high|medium|low",
      "category": "architecture|domain-boundary|naming|coupling|abstraction|maintainability|security|compliance",
      "overlay": "default|senior-eye|security|hipaa-soc2",
      "file": "<repo-relative path>",
      "line_start": <integer>,
      "line_end": <integer>,
      "title": "<short title, <=120 chars>",
      "rationale": "<markdown body, brief>",
      "suggested_remediation": "<markdown / code block or null>"
    }
  ]
}
\`\`\`

Rules:
- Each finding's (file, line_start, line_end) MUST anchor to a line
  visible in the provided diff (an added or modified RIGHT-side line).
  Structural findings not tied to a specific line should be anchored to
  the first changed line in the relevant file.
- The default rubric for ARCHITECTURE mode caps at severity 'medium'.
  Only the security and hipaa-soc2 overlays may emit 'high' or 'critical'.
- Avoid stylistic nits unless they expose a structural problem.
- Labels MUST be under the \`agent-review/\` prefix. Examples:
  \`agent-review/architecture-concern\`, \`agent-review/security-concern\`,
  \`agent-review/compliance-concern\`, \`agent-review/needs-decision\`.
- If you find nothing actionable, emit:
  { "schema_version": "2", "summary_markdown": "No actionable findings.",
    "labels": [], "categories_present": [], "findings": [] }

## Diff

\`\`\`diff
EOF
  cat "$FILTERED_DIFF"
  echo '```'
} > "$PROMPT_FILE"

RAW_OUTPUT=$(mktemp)
trap 'rm -f "$FILTERED_DIFF" "$PROMPT_FILE" "$RAW_OUTPUT"' EXIT

# SECURITY: lock claude down to JUST the LLM call — no tool access at all.
#
# We use THREE layers of defense, because a blocklist of built-in tools
# alone is fragile (new Claude Code releases can add tools that bypass it,
# and MCP tools are not covered by --disallowed-tools at all):
#
#   1. --disallowed-tools — exhaustive blocklist of every built-in tool
#      family known at time of writing. Includes Skill, TodoWrite,
#      AskUserQuestion, ToolSearch, ExitPlanMode etc. that the prior
#      revision missed. Pinned CLAUDE_CODE_VERSION in the Dockerfile is
#      what makes this list deterministic.
#
#   2. --strict-mcp-config + an empty --mcp-config file — disables MCP
#      auto-discovery and forces zero MCP servers. Without this, any
#      .mcp.json that lands in the workspace (or a future feature that
#      defaults to discovery) would let MCP tools bypass the blocklist.
#
#   3. The Dockerfile pins CLAUDE_CODE_VERSION to a known version (not
#      `latest`). New Claude Code releases that add tools cannot reach
#      production until we explicitly bump and re-review the blocklist.
#
# This is the "the LLM has no tools" boundary made actually true.

EMPTY_MCP_CONFIG=$(mktemp)
echo '{"mcpServers":{}}' > "$EMPTY_MCP_CONFIG"
trap 'rm -f "$FILTERED_DIFF" "$PROMPT_FILE" "$EMPTY_MCP_CONFIG"' EXIT

if ! claude --print --output-format json \
      --disallowed-tools "Bash" \
      --disallowed-tools "BashOutput" \
      --disallowed-tools "KillShell" \
      --disallowed-tools "Edit" \
      --disallowed-tools "Write" \
      --disallowed-tools "NotebookEdit" \
      --disallowed-tools "NotebookRead" \
      --disallowed-tools "Read" \
      --disallowed-tools "Glob" \
      --disallowed-tools "Grep" \
      --disallowed-tools "WebFetch" \
      --disallowed-tools "WebSearch" \
      --disallowed-tools "Task" \
      --disallowed-tools "SlashCommand" \
      --disallowed-tools "Skill" \
      --disallowed-tools "TodoWrite" \
      --disallowed-tools "AskUserQuestion" \
      --disallowed-tools "ToolSearch" \
      --disallowed-tools "ExitPlanMode" \
      --strict-mcp-config \
      --mcp-config "$EMPTY_MCP_CONFIG" \
      < "$PROMPT_FILE" > "$RAW_OUTPUT" 2>&1; then
  echo "::error::claude invocation failed"
  head -50 "$RAW_OUTPUT" >&2 || true
  emit_malformed "claude invocation failed"
  exit 0
fi

MODEL_JSON=$(jq -r '.result // .' "$RAW_OUTPUT" 2>/dev/null || cat "$RAW_OUTPUT")
MODEL_JSON=$(echo "$MODEL_JSON" \
  | sed -e 's/^```json//' -e 's/^```//' -e 's/```$//')

if ! echo "$MODEL_JSON" | jq empty >/dev/null 2>&1; then
  echo "::error::claude returned non-JSON output"
  echo "$MODEL_JSON" | head -30 >&2
  emit_malformed "claude returned non-JSON output"
  exit 0
fi

if [[ ${#SELECTED_OVERLAYS[@]} -eq 0 ]]; then
  OVERLAY_JSON='[]'
else
  OVERLAY_JSON=$(printf '%s\n' "${SELECTED_OVERLAYS[@]}" | jq -R . | jq -s .)
fi

echo "$MODEL_JSON" | jq \
  --arg head "$HEAD_SHA" \
  --arg base "$BASE_SHA" \
  --arg mode "$REVIEW_MODE" \
  --argjson overlays "$OVERLAY_JSON" \
  --argjson max "$MAX_FINDINGS" \
  '
  {
    schema_version: "2",
    head_sha: $head,
    base_sha: $base,
    review_mode: $mode,
    overlays_applied: $overlays,
    parser_status: "ok",
    summary_markdown: (.summary_markdown // "No summary provided."),
    labels: ((.labels // []) | map(select(startswith("agent-review/")))),
    categories_present: (.categories_present // []),
    findings: (
      (.findings // [])
      | .[0:$max]
      | map(. + {
          fingerprint: (
            (.category // "unknown") + "|" +
            (.file // "unknown") + "|" +
            ((.line_start // 0) | tostring) + "|" +
            (.title // "untitled")
            | @base64
          )
        })
    )
  }
  ' > "$OUTPUT_PATH"

echo "::notice::agent emitted $(jq '.findings | length' "$OUTPUT_PATH") finding(s) to $OUTPUT_PATH"
