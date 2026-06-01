#!/usr/bin/env bash
#
# test-coverage.sh - flag changed source files that have no corresponding
# test file change in the same PR. Coarse but useful: a "behavior change
# without a test change" is the senior-eye lens's single most common
# finding.
#
# Usage:  test-coverage.sh <diff.patch>
# Output: tab-separated lines:
#           UNTESTED  <source-file>  (no matching test file in diff)
#         or, if all changes are paired:
#           OK  all changed source files have a matching test file in the diff
#
# Heuristics for what counts as "matching":
#   src/foo.ts                -> test/foo.test.ts, src/foo.test.ts, src/__tests__/foo.test.ts
#   pkg/x/y.go                -> pkg/x/y_test.go
#   app/models/user.py        -> tests/test_user.py, app/models/test_user.py
#
# Files NOT considered source (skipped from the check entirely):
#   - any test file (by the same heuristic)
#   - generated code (paths matching dist/, build/, generated/, .pb.go, etc.)
#   - manifests (package.json, requirements.txt, go.mod, etc.)
#   - docs, configs, lockfiles
#   - the PR's own test files (we look at OTHER changed test files for matches)

set -euo pipefail

DIFF="${1:?usage: test-coverage.sh <diff.patch>}"

if [[ ! -f "$DIFF" ]]; then
  echo "diff file not found: $DIFF" >&2
  exit 1
fi

CHANGED=$(grep -E '^diff --git ' "$DIFF" \
  | awk '{print $4}' \
  | sed 's|^b/||' \
  | sort -u)

is_test() {
  case "$1" in
    */test/*|*/tests/*|*/__tests__/*|*/spec/*|*/specs/*) return 0 ;;
    *_test.go|*_test.py|*_test.rb) return 0 ;;
    *.test.ts|*.spec.ts|*.test.tsx|*.spec.tsx|*.test.js|*.spec.js|*.test.jsx|*.spec.jsx) return 0 ;;
    *) return 1 ;;
  esac
}

is_skip() {
  case "$1" in
    # Manifests / lockfiles
    */package.json|package.json) return 0 ;;
    */package-lock.json|package-lock.json) return 0 ;;
    */yarn.lock|yarn.lock|*/pnpm-lock.yaml|pnpm-lock.yaml) return 0 ;;
    */requirements*.txt|requirements*.txt) return 0 ;;
    */pyproject.toml|pyproject.toml|*/poetry.lock|poetry.lock) return 0 ;;
    */Cargo.toml|Cargo.toml|*/Cargo.lock|Cargo.lock) return 0 ;;
    */go.mod|go.mod|*/go.sum|go.sum) return 0 ;;
    */Gemfile|Gemfile|*/Gemfile.lock|Gemfile.lock) return 0 ;;
    # Docs / configs
    *.md|*.txt|*.rst|LICENSE|README|*.gitignore|*.editorconfig|*.dockerignore) return 0 ;;
    *.yml|*.yaml|*.toml|*.ini|*.cfg|*.json) return 0 ;;
    Dockerfile|*/Dockerfile) return 0 ;;
    Makefile|*/Makefile) return 0 ;;
    # Generated / vendored
    */dist/*|*/build/*|*/out/*|*/.next/*|*/generated/*) return 0 ;;
    */node_modules/*|*/vendor/*) return 0 ;;
    *.pb.go|*.pb.ts|*_pb2.py) return 0 ;;
    # Type-only / declaration files
    *.d.ts) return 0 ;;
    *) return 1 ;;
  esac
}

# Build a set of test files present in the diff.
TEST_FILES=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if is_test "$f"; then
    TEST_FILES+="$f"$'\n'
  fi
done <<< "$CHANGED"

# Does the diff contain a test file that "matches" a given source file?
has_matching_test() {
  local src="$1"
  local base="${src##*/}"          # foo.ts
  local stem="${base%.*}"           # foo
  local lang_ext="${base##*.}"
  [[ -z "$TEST_FILES" ]] && return 1
  while IFS= read -r tf; do
    [[ -z "$tf" ]] && continue
    case "$tf" in
      *${stem}_test.go|*${stem}_test.py|*${stem}_test.rb)             return 0 ;;
      *${stem}.test.ts|*${stem}.spec.ts|*${stem}.test.tsx|*${stem}.spec.tsx) return 0 ;;
      *${stem}.test.js|*${stem}.spec.js|*${stem}.test.jsx|*${stem}.spec.jsx) return 0 ;;
      */tests/test_${stem}.py|*/test_${stem}.py)                       return 0 ;;
      */__tests__/${stem}.*)                                           return 0 ;;
    esac
  done <<< "$TEST_FILES"
  return 1
}

UNTESTED=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if is_test "$f"; then continue; fi
  if is_skip "$f"; then continue; fi
  if has_matching_test "$f"; then continue; fi
  printf 'UNTESTED\t%s\t(no matching test file in diff)\n' "$f"
  UNTESTED=$((UNTESTED+1))
done <<< "$CHANGED"

if [[ "$UNTESTED" -eq 0 ]]; then
  echo "OK	all changed source files have a matching test file in the diff"
fi
