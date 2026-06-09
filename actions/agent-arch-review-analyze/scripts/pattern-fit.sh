#!/usr/bin/env bash
#
# pattern-fit.sh - for a (new) file, find the most structurally similar
# existing files in the repo. Helps the reviewer ground "this PR
# introduces a new pattern where an existing one would have sufficed."
#
# Usage:  pattern-fit.sh <new-file-path> <repo-root> [max-results]
# Output: tab-separated lines:
#           <new-file>  <similar-file>  <similarity-score>  <reason>
#
# Similarity is a coarse heuristic:
#   - Same layer (per layer-classify.sh)              +3
#   - Same file extension                             +1
#   - Same parent directory                           +2
#   - Same grandparent directory                      +1
#   - Filename token overlap (e.g. user-controller vs +1..3 per shared token
#     order-controller)
# Top N results are returned ordered by score descending.

set -euo pipefail

F="${1:?usage: pattern-fit.sh <new-file> <repo-root> [max-results]}"
REPO="${2:?usage: pattern-fit.sh <new-file> <repo-root> [max-results]}"
MAX="${3:-3}"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ ! -f "$REPO/$F" && ! -f "$F" ]]; then
  exit 0
fi

# Compute features of the target file.
SELF_LAYER=$("${SCRIPT_DIR}/layer-classify.sh" "$F" | awk -F'\t' '{print $2}')
SELF_EXT="${F##*.}"
SELF_PARENT=$(dirname "$F")
SELF_GRANDPARENT=$(dirname "$SELF_PARENT")
SELF_BASE=$(basename "$F" ".$SELF_EXT")
# Tokenize on common separators
SELF_TOKENS=$(echo "$SELF_BASE" | tr 'A-Z-_.' 'a-z   ' | tr -s ' ')

# Walk repo and score each existing file.
RESULTS=$(mktemp)
trap 'rm -f "$RESULTS"' EXIT

find "$REPO" -type f \
  \( -name "*.${SELF_EXT}" -o -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.py" -o -name "*.go" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" -not -path "*/build/*" \
  2>/dev/null | while IFS= read -r candidate; do
    REL="${candidate#${REPO}/}"
    [[ "$REL" == "$F" ]] && continue

    score=0
    reasons=""

    # Same layer?
    cand_layer=$("${SCRIPT_DIR}/layer-classify.sh" "$REL" | awk -F'\t' '{print $2}')
    if [[ "$cand_layer" == "$SELF_LAYER" && "$cand_layer" != "unknown" ]]; then
      score=$((score+3)); reasons="${reasons}layer "
    fi

    # Same extension?
    cand_ext="${REL##*.}"
    if [[ "$cand_ext" == "$SELF_EXT" ]]; then
      score=$((score+1)); reasons="${reasons}ext "
    fi

    # Same parent dir?
    cand_parent=$(dirname "$REL")
    if [[ "$cand_parent" == "$SELF_PARENT" ]]; then
      score=$((score+2)); reasons="${reasons}sibling "
    elif [[ "$(dirname "$cand_parent")" == "$SELF_GRANDPARENT" ]]; then
      score=$((score+1)); reasons="${reasons}cousin "
    fi

    # Filename token overlap.
    cand_base=$(basename "$REL" ".$cand_ext")
    cand_tokens=$(echo "$cand_base" | tr 'A-Z-_.' 'a-z   ' | tr -s ' ')
    overlap=0
    for t in $SELF_TOKENS; do
      [[ "${#t}" -lt 3 ]] && continue   # skip short common tokens (the, app, src)
      if [[ " $cand_tokens " == *" $t "* ]]; then
        overlap=$((overlap+1))
      fi
    done
    if [[ "$overlap" -gt 0 ]]; then
      score=$((score + overlap))
      reasons="${reasons}tokens($overlap) "
    fi

    if [[ "$score" -gt 0 ]]; then
      printf '%d\t%s\t%s\n' "$score" "$REL" "${reasons% }"
    fi
  done | sort -t$'\t' -k1,1nr | head -n "$MAX" > "$RESULTS"

while IFS=$'\t' read -r score similar reason; do
  printf '%s\t%s\t%d\t%s\n' "$F" "$similar" "$score" "$reason"
done < "$RESULTS"
