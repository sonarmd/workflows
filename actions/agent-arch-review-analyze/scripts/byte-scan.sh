#!/usr/bin/env bash
#
# byte-scan.sh — flag changed files containing suspicious bytes that an
# LLM may have introduced: NBSP, smart quotes, em/en dashes, zero-width
# characters, control bytes, invalid UTF-8, roff escape misuse, shell
# PATH clobbers, and Markdown fence breakage.
#
# Powered by the vendored guarded-fs CLI (see ../lib/guarded-fs/).
# Uses python3 from the runner (ubuntu-latest has it; no install step).
# Stdlib only — no pip dependencies.
#
# Usage:  byte-scan.sh <diff.patch> <repo-root>
# Output: tab-separated lines:
#           SUSPICIOUS  <file>  <findings_count>  <reasons-csv>
#         or, if all changes are clean:
#           OK  no suspicious bytes detected in changed files
#
# Files NOT scanned (skipped):
#   - binaries / lockfiles / images (handled by guarded-fs binary_skip_globs)
#   - files removed in this PR (we scan the post-image only)
#   - files larger than 1 MiB (guarded-fs handles, but we pre-skip to keep
#     CI fast)

set -euo pipefail

DIFF="${1:?usage: byte-scan.sh <diff.patch> <repo-root>}"
REPO="${2:?usage: byte-scan.sh <diff.patch> <repo-root>}"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
GUARDED_FS="${SCRIPT_DIR}/../lib/guarded-fs/bin/guarded-fs"

if [[ ! -f "$DIFF" ]]; then
  echo "diff file not found: $DIFF" >&2
  exit 1
fi
if [[ ! -d "$REPO" ]]; then
  echo "repo dir not found: $REPO" >&2
  exit 1
fi
if [[ ! -x "$GUARDED_FS" ]]; then
  echo "guarded-fs CLI not found or not executable: $GUARDED_FS" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not on PATH; byte-scan requires python3 (stdlib only)" >&2
  exit 1
fi

# Redirect audit log to the runner temp dir — never inside the repo.
export GUARDED_FS_AUDIT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/guarded-fs-audit.jsonl"

# Extract list of changed files (post-image paths). Skip pure-deletes.
CHANGED=$(grep -E '^diff --git ' "$DIFF" \
  | awk '{print $4}' \
  | sed 's|^b/||' \
  | sort -u || true)

SUSPICIOUS_COUNT=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  target="$REPO/$f"
  [[ ! -f "$target" ]] && continue
  # Pre-skip > 1 MiB.
  size=$(wc -c <"$target" 2>/dev/null || echo 0)
  if [[ "$size" -gt 1048576 ]]; then continue; fi

  # Scan one file. guarded-fs scan returns non-zero on blocked; we accept
  # that and parse the JSON either way.
  JSON=$("$GUARDED_FS" scan "$target" 2>/dev/null || true)
  if [[ -z "$JSON" ]]; then continue; fi

  STATUS=$(printf '%s' "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null || echo "")
  if [[ "$STATUS" != "blocked" && "$STATUS" != "suspicious" ]]; then
    continue
  fi

  # Collect distinct reasons + total findings count.
  read -r COUNT REASONS < <(printf '%s' "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
findings = []
for f in d.get('files', []):
    findings.extend(f.get('findings', []))
if not findings and d.get('findings'):
    findings = d['findings']
reasons = sorted({f.get('reason','?') for f in findings})
print(len(findings), ','.join(reasons))
" 2>/dev/null || echo "0 unknown")

  printf 'SUSPICIOUS\t%s\t%s\t%s\n' "$f" "$COUNT" "$REASONS"
  SUSPICIOUS_COUNT=$((SUSPICIOUS_COUNT+1))
done <<< "$CHANGED"

if [[ "$SUSPICIOUS_COUNT" -eq 0 ]]; then
  echo "OK	no suspicious bytes detected in changed files"
fi
