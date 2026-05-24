#!/usr/bin/env bash
#
# bootstrap-agent-review.sh — opens a DRAFT PR in each named repo that
# adds `per-repo/_template/.github/workflows/agent-architecture-review.yml`
# to that repo's `.github/workflows/`. Path B (fallback) adoption.
#
# Usage:
#   scripts/bootstrap-agent-review.sh REPO [REPO ...]
#   scripts/bootstrap-agent-review.sh --from-file repos.txt
#
# Requires: gh CLI logged in with repo: write access to each target.
#
# Idempotent: skips repos that already have the file. Skips repos that
# already have an open PR titled "chore: add agent architecture review".

set -euo pipefail

TEMPLATE_PATH="$(git rev-parse --show-toplevel)/per-repo/_template/.github/workflows/agent-architecture-review.yml"
TARGET_PATH=".github/workflows/agent-architecture-review.yml"
BRANCH_NAME="chore/add-agent-architecture-review"
PR_TITLE="chore: add agent architecture review"
PR_BODY_FILE="$(mktemp)"
trap 'rm -f "$PR_BODY_FILE"' EXIT

cat > "$PR_BODY_FILE" <<'EOF'
Adds the org-standard agent architecture review workflow.

This PR is a thin caller that delegates to `sonarmd/workflows`. All
behavior is controlled centrally. To tune for this repo, add a
`.github/agent-review.yml`; see template at
`sonarmd/workflows/per-repo/_template/.github/agent-review.yml`.

## What this does

- Runs an agent-based reviewer on every PR (opened/synchronize/reopened)
- Posts a summary comment + inline comments + a check run + labels
- Advisory by default — never blocks merge
- LLM has no GitHub write access; deterministic publisher posts findings

## What this needs

- `CLAUDE_CODE_OAUTH_TOKEN` secret (preferred — subscription billing).
  Get with `claude setup-token` locally.
- _Or_ `ANTHROPIC_API_KEY` (per-token billing fallback).
- Org-level secret works for either.

## What this changes

- New file: `.github/workflows/agent-architecture-review.yml` (25 lines)
- Nothing else.

🤖 Opened by bootstrap-agent-review.sh
EOF

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "::error::template not found at $TEMPLATE_PATH" >&2
  exit 2
fi

REPOS=()
if [[ "${1:-}" == "--from-file" ]]; then
  shift
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    REPOS+=("$line")
  done < "$1"
else
  REPOS=("$@")
fi

if [[ ${#REPOS[@]} -eq 0 ]]; then
  echo "usage: $0 REPO [REPO ...]   |   $0 --from-file repos.txt" >&2
  exit 2
fi

# Track per-repo outcomes for the summary table + non-zero exit on any failure.
declare -a SUCCEEDED=()
declare -a SKIPPED=()
declare -a FAILED=()

record_failure() {
  local repo="$1"
  local stage="$2"
  local reason="$3"
  FAILED+=("${repo}|${stage}|${reason}")
  echo "  FAILED [${stage}]: ${reason}"
}

for repo in "${REPOS[@]}"; do
  echo "=== $repo ==="

  # Skip if already adopted.
  if gh api "repos/${repo}/contents/${TARGET_PATH}" >/dev/null 2>&1; then
    echo "  already has ${TARGET_PATH}; skipping"
    SKIPPED+=("${repo}|already adopted")
    continue
  fi

  # Skip if there's already an open PR with this title. Do NOT redirect
  # stderr into stdout — gh's release-notice warnings on stdout would
  # otherwise look like PR numbers and trick the heuristic into skipping
  # the repo. Validate the result is digit-only before treating it as a
  # PR number list.
  EXISTING=$(gh pr list -R "$repo" --state open --search "$PR_TITLE in:title" --json number --jq '.[].number' 2>/dev/null || true)
  if [[ -n "$EXISTING" ]] && printf '%s\n' "$EXISTING" | grep -qE '^[0-9]+$'; then
    echo "  already has open bootstrap PR(s): $EXISTING; skipping"
    SKIPPED+=("${repo}|open PR #${EXISTING}")
    continue
  fi

  WORKDIR=$(mktemp -d)
  # Capture stderr so we know WHY the clone failed (auth vs not-found vs net).
  CLONE_ERR=$(gh repo clone "$repo" "$WORKDIR" -- --depth=1 2>&1 >/dev/null) || {
    record_failure "$repo" "clone" "${CLONE_ERR}"
    rm -rf "$WORKDIR"
    continue
  }

  # Capture stderr via a tempfile, NOT process substitution. Bash's
  # `2> >(VAR=$(cat); export VAR)` runs the assignment in a subshell that
  # cannot mutate the parent — STAGE_ERR would always be empty. Using a
  # tempfile sidesteps the subshell entirely.
  STAGE_ERR_FILE=$(mktemp)
  if ! ( cd "$WORKDIR" && {
    DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name) || { echo "could not resolve default branch" >&2; exit 1; }
    git checkout -b "$BRANCH_NAME" "origin/${DEFAULT_BRANCH}" || { echo "checkout failed" >&2; exit 1; }
    mkdir -p .github/workflows
    cp "$TEMPLATE_PATH" "$TARGET_PATH" || { echo "copy template failed" >&2; exit 1; }
    git add "$TARGET_PATH"
    git -c commit.gpgsign=true commit -m "chore: add agent architecture review" || { echo "commit failed (signing? config?)" >&2; exit 1; }
    git push -u origin "$BRANCH_NAME" || { echo "push failed (permissions?)" >&2; exit 1; }
    gh pr create \
      --draft \
      --title "$PR_TITLE" \
      --body-file "$PR_BODY_FILE" \
      --base "$DEFAULT_BRANCH" || { echo "gh pr create failed" >&2; exit 1; }
  } ) 2> "$STAGE_ERR_FILE"; then
    STAGE_ERR=$(tr '\n' ' ' < "$STAGE_ERR_FILE" | sed 's/  */ /g' | cut -c1-300)
    record_failure "$repo" "pr-open" "${STAGE_ERR:-no stderr captured}"
    rm -rf "$WORKDIR" "$STAGE_ERR_FILE"
    continue
  fi
  rm -f "$STAGE_ERR_FILE"

  rm -rf "$WORKDIR"
  echo "  PR opened"
  SUCCEEDED+=("$repo")
done

# Summary table — operator needs visibility on bulk runs.
echo
echo "=========================================="
echo "  Bootstrap summary"
echo "=========================================="
echo "  succeeded: ${#SUCCEEDED[@]}"
echo "  skipped:   ${#SKIPPED[@]}"
echo "  failed:    ${#FAILED[@]}"
echo
if [[ ${#SUCCEEDED[@]} -gt 0 ]]; then
  echo "  Succeeded:"
  for r in "${SUCCEEDED[@]}"; do echo "    + $r"; done
fi
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo "  Skipped:"
  for entry in "${SKIPPED[@]}"; do
    echo "    - ${entry%%|*}   (${entry#*|})"
  done
fi
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "  Failed:"
  for entry in "${FAILED[@]}"; do
    repo="${entry%%|*}"; rest="${entry#*|}"; stage="${rest%%|*}"; reason="${rest#*|}"
    printf "    x %-40s [%s] %s\n" "$repo" "$stage" "$reason"
  done
  echo
  echo "exiting non-zero — ${#FAILED[@]} repo(s) need attention."
  exit 1
fi

echo "done."
