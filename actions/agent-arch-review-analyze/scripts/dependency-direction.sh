#!/usr/bin/env bash
#
# dependency-direction.sh — flag inward-pointing dependency violations.
#
# Clean Architecture rule: dependencies point INWARD only.
#   interface → application → domain
#   infrastructure → domain  (NOT domain → infrastructure)
#   presentation → application → domain
#
# This script extracts imports from a file and classifies the imported
# module's layer using the same heuristic as layer-classify.sh. It flags
# imports that point OUTWARD (an inner layer pulling on an outer one),
# which are the canonical "leaky boundary" smell.
#
# Usage:  dependency-direction.sh <file-path> <repo-root>
# Output: tab-separated lines:
#           VIOLATION  <file>  imports  <imported-path>  (<self-layer> → <imp-layer>)
#         or:
#           OK         <file>  (no violations among N imports)

set -euo pipefail

F="${1:?usage: dependency-direction.sh <file> <repo-root>}"
REPO="${2:?usage: dependency-direction.sh <file> <repo-root>}"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ ! -f "$F" ]]; then
  exit 0
fi

# Map layer name to dependency rank (lower = more inward).
layer_rank() {
  case "$1" in
    domain)         echo 1 ;;
    application)    echo 2 ;;
    interface|presentation) echo 3 ;;
    infrastructure) echo 3 ;;
    cross-cutting)  echo 9 ;;  # cross-cutting can go anywhere
    test)           echo 9 ;;
    unknown)        echo 9 ;;
  esac
}

SELF_LAYER=$("${SCRIPT_DIR}/layer-classify.sh" "$F" | awk -F'\t' '{print $2}')
SELF_RANK=$(layer_rank "$SELF_LAYER")

# Extract per-language imports. We only care about REPO-INTERNAL imports
# (relative paths or paths that resolve inside REPO). External imports
# (npm packages, stdlib, etc.) are not layer-classified.
extract_imports() {
  local f="$1"
  case "$f" in
    *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs)
      # Match `import ... from '...'` and `require('...')`. Capture the path.
      grep -oE "from[[:space:]]+['\"][^'\"]+['\"]|require[[:space:]]*\([[:space:]]*['\"][^'\"]+['\"]" "$f" 2>/dev/null \
        | grep -oE "['\"][^'\"]+['\"]" | tr -d "\"'"
      ;;
    *.py)
      # `from X import Y` and `import X`.
      grep -E '^[[:space:]]*(from|import)[[:space:]]+[A-Za-z0-9_.]+' "$f" 2>/dev/null \
        | awk '{ if ($1=="from") print $2; else print $2 }' \
        | awk -F. '{print $1"/"$2"/"$3}' | sed 's|//*$||' | sed 's|//*|/|g'
      ;;
    *.go)
      # Either single-line `import "..."` or block `import ( "..." )`.
      awk 'BEGIN { in_block=0 }
           /^[[:space:]]*import[[:space:]]*\(/ { in_block=1; next }
           /^[[:space:]]*\)/ { in_block=0; next }
           in_block { print }
           /^[[:space:]]*import[[:space:]]+"/ { print }' "$f" 2>/dev/null \
        | grep -oE '"[^"]+"' | tr -d '"'
      ;;
    *)
      ;;
  esac
}

# Resolve an import path to a repo-relative file. Returns empty if not in repo.
resolve_in_repo() {
  local imp="$1" base_dir="$2"
  # Relative imports
  if [[ "$imp" == .* ]]; then
    local resolved
    resolved=$(cd "$base_dir" 2>/dev/null && cd "$(dirname "$imp")" 2>/dev/null && pwd)/$(basename "$imp")
    [[ -z "$resolved" ]] && return
    # Strip REPO prefix to make repo-relative.
    echo "${resolved#${REPO}/}"
    return
  fi
  # Repo-internal absolute-ish paths
  if [[ -e "${REPO}/${imp}" ]]; then
    echo "$imp"
    return
  fi
}

VIOLATIONS=0
TOTAL=0
while IFS= read -r imp; do
  [[ -z "$imp" ]] && continue
  TOTAL=$((TOTAL+1))
  RESOLVED=$(resolve_in_repo "$imp" "$(dirname "$F")")
  [[ -z "$RESOLVED" ]] && continue   # external / unresolved — skip

  IMP_LAYER=$("${SCRIPT_DIR}/layer-classify.sh" "${REPO}/${RESOLVED}" | awk -F'\t' '{print $2}')
  IMP_RANK=$(layer_rank "$IMP_LAYER")

  # Cross-cutting / test / unknown — neutral.
  if [[ "$SELF_RANK" -ge 9 || "$IMP_RANK" -ge 9 ]]; then
    continue
  fi

  # Inner (lower rank) importing from outer (higher rank) is the violation.
  if [[ "$SELF_RANK" -lt "$IMP_RANK" ]]; then
    printf 'VIOLATION\t%s\timports\t%s\t(%s → %s)\n' "$F" "$RESOLVED" "$SELF_LAYER" "$IMP_LAYER"
    VIOLATIONS=$((VIOLATIONS+1))
  fi
done < <(extract_imports "$F")

if [[ "$VIOLATIONS" -eq 0 ]]; then
  printf 'OK\t%s\t(no violations among %d imports)\n' "$F" "$TOTAL"
fi
