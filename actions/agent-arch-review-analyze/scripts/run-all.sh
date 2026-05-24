#!/usr/bin/env bash
#
# run-all.sh — orchestrator. Runs every analyzer over the changed files
# in a PR and produces a single markdown report at the output path.
#
# Usage:
#   run-all.sh <diff.patch> <repo-root> <output.md>
#
# Expected env:
#   none
#
# Output: a markdown report with sections:
#   - File metrics (lines, funcs, max func, max depth) per changed file
#   - Layer classification per changed file
#   - Dependency-direction violations
#   - Pattern fit for net-new files

set -euo pipefail

DIFF="${1:?usage: run-all.sh <diff.patch> <repo-root> <output.md>}"
REPO="${2:?usage: run-all.sh <diff.patch> <repo-root> <output.md>}"
OUT="${3:?usage: run-all.sh <diff.patch> <repo-root> <output.md>}"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ ! -f "$DIFF" ]]; then
  echo "diff file not found: $DIFF" >&2
  exit 1
fi
if [[ ! -d "$REPO" ]]; then
  echo "repo dir not found: $REPO" >&2
  exit 1
fi

# Extract list of changed files from unified diff. Filter to source files
# (rough heuristic; skip lockfiles, generated, vendored).
CHANGED=$(grep -E '^diff --git ' "$DIFF" \
  | awk '{print $4}' \
  | sed 's|^b/||' \
  | grep -vE '(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|go\.sum|Cargo\.lock|poetry\.lock|\.min\.(js|css)$)' \
  | grep -vE '^(node_modules/|vendor/|dist/|build/|\.git/)' \
  | sort -u || true)

NET_NEW=$(grep -E '^diff --git ' "$DIFF" \
  | awk '{print $4}' \
  | sed 's|^b/||' \
  | while IFS= read -r f; do
      # A net-new file is one where the diff has `new file mode` shortly after.
      if grep -A2 -E "^diff --git a/[^ ]+ b/${f}$" "$DIFF" | grep -q '^new file mode'; then
        echo "$f"
      fi
    done | sort -u || true)

CHANGED_COUNT=$(echo "$CHANGED" | grep -c . || echo 0)
NEW_COUNT=$(echo "$NET_NEW" | grep -c . || echo 0)

# Build the report.
{
  echo "# Pre-Computed Architecture Analysis"
  echo
  echo "Computed by the architecture-analyzer toolset before the agent was invoked. Use these as grounding evidence — not as findings to repeat verbatim, but as facts the reviewer can cite."
  echo
  echo "**Changed files:** ${CHANGED_COUNT}  |  **Net-new files:** ${NEW_COUNT}"
  echo

  echo "## File metrics"
  echo
  echo "| File | Lines | Funcs | Max func | Max depth |"
  echo "|---|---:|---:|---:|---:|"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    target="$REPO/$f"
    if [[ -f "$target" ]]; then
      "${SCRIPT_DIR}/file-metrics.sh" "$target" \
        | awk -F'\t' -v f="$f" '{ printf "| `%s` | %s | %s | %s | %s |\n", f, $2, $3, $4, $5 }'
    fi
  done <<< "$CHANGED"
  echo
  echo "_Max func > 60 lines or max depth > 5 typically warrants a closer look._"
  echo

  echo "## Layer classification"
  echo
  echo "Heuristic guess (path-based) of each changed file's Clean Architecture layer."
  echo
  echo "| File | Guessed layer |"
  echo "|---|---|"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    "${SCRIPT_DIR}/layer-classify.sh" "$f" \
      | awk -F'\t' '{ printf "| `%s` | %s |\n", $1, $2 }'
  done <<< "$CHANGED"
  echo
  echo "_Files classified \`unknown\` may be miscategorized — confirm against the actual content before flagging boundary concerns._"
  echo

  echo "## Dependency-direction violations"
  echo
  echo "Imports that point OUTWARD (an inner layer pulling on an outer one) — canonical leaky-boundary smell."
  echo
  VIOL_COUNT=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    target="$REPO/$f"
    if [[ -f "$target" ]]; then
      while IFS= read -r line; do
        if [[ "$line" == VIOLATION* ]]; then
          VIOL_COUNT=$((VIOL_COUNT+1))
          echo "- $line" | sed 's/^- VIOLATION\t/- **VIOLATION** /; s/\timports\t/ imports /; s/\t/ — /g'
        fi
      done < <("${SCRIPT_DIR}/dependency-direction.sh" "$target" "$REPO" 2>/dev/null || true)
    fi
  done <<< "$CHANGED"
  if [[ "$VIOL_COUNT" -eq 0 ]]; then
    echo "_No dependency-direction violations detected among repo-internal imports._"
  fi
  echo

  if [[ "$NEW_COUNT" -gt 0 ]]; then
    echo "## Pattern fit (net-new files)"
    echo
    echo "For each net-new file, the 3 most structurally similar existing files (by layer, dir, name tokens). If a similar file already exists, ask whether the new pattern is justified or whether the existing one would have served."
    echo
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      echo "### \`$f\`"
      echo
      RESULTS=$("${SCRIPT_DIR}/pattern-fit.sh" "$f" "$REPO" 3 2>/dev/null || true)
      if [[ -z "$RESULTS" ]]; then
        echo "_No structurally similar file found in the repo._"
      else
        echo "| Similar file | Score | Reason |"
        echo "|---|---:|---|"
        echo "$RESULTS" | awk -F'\t' '{ printf "| `%s` | %s | %s |\n", $2, $3, $4 }'
      fi
      echo
    done <<< "$NET_NEW"
  fi

  echo "## How to use this report"
  echo
  echo "- Tie qualitative findings to specific rows above. A finding that says \"this function is too long\" should cite the row showing the actual line count."
  echo "- If a row contradicts a finding you were about to make, drop the finding."
  echo "- Treat layer classifications as suggestions — verify against file content for the few cases where the path heuristic might mislead."
} > "$OUT"

echo "wrote analysis to $OUT ($(wc -l < "$OUT") lines)"
