#!/usr/bin/env bash
#
# file-metrics.sh — language-agnostic structural metrics for a file.
#
# Usage:  file-metrics.sh <file-path>
# Output: <file>\t<lines>\t<funcs>\t<max-func-len>\t<max-depth>
#
# Metrics:
#   lines         — total non-blank, non-comment lines (best-effort)
#   funcs         — function-like declarations matched by a coarse regex
#                   across JS/TS/Python/Go/Rust/Java/C-family. Designed
#                   to be conservative (under-count rather than over-count
#                   to avoid false signal on string literals etc.)
#   max-func-len  — longest contiguous block following a function declaration
#                   that stays at an indentation > the declaration's indent
#                   (heuristic; misses one-liners and braced styles a bit)
#   max-depth     — deepest leading-whitespace indent across the file
#                   (proxy for control-flow nesting depth)

set -euo pipefail

F="${1:?usage: file-metrics.sh <file>}"

if [[ ! -f "$F" ]]; then
  printf '%s\t0\t0\t0\t0\n' "$F"
  exit 0
fi

# total non-blank, non-comment lines
LINES=$(awk '
  /^[[:space:]]*$/ { next }
  /^[[:space:]]*(#|\/\/|--|;|\*).*/ { next }
  { c++ }
  END { print c+0 }
' "$F")

# function count — coarse regex covering common forms
FUNCS=$(grep -cE '^[[:space:]]*(function[[:space:]]+[A-Za-z_]|def[[:space:]]+[A-Za-z_]|func[[:space:]]+\(?[A-Za-z_]|fn[[:space:]]+[A-Za-z_]|public[[:space:]]+[a-z]+[[:space:]]+[A-Za-z_].*\(|private[[:space:]]+[a-z]+[[:space:]]+[A-Za-z_].*\(|protected[[:space:]]+[a-z]+[[:space:]]+[A-Za-z_].*\(|static[[:space:]]+[a-z]+[[:space:]]+[A-Za-z_].*\(|[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[=:][[:space:]]*\(?[A-Za-z_, ]*\)?[[:space:]]*=>[[:space:]]*[{(])' "$F" 2>/dev/null || echo 0)

# max nesting depth — count leading spaces (assume 2 or 4-space indent)
MAX_DEPTH=$(awk '
  /^[[:space:]]*$/ { next }
  {
    match($0, /^[[:space:]]*/)
    ws = RLENGTH
    # Try 2-space then 4-space; take the smaller plausible depth.
    d2 = int(ws / 2)
    d4 = int(ws / 4)
    d = (d4 >= 1 && (ws % 4 == 0)) ? d4 : d2
    if (d > maxd) maxd = d
  }
  END { print maxd+0 }
' "$F")

# max function length — scan for function-like declarations, then count
# subsequent lines at greater indent until indent returns to declaration level.
MAX_FUNC_LEN=$(awk '
  function flush() {
    if (in_func && (cur_len > max_len)) max_len = cur_len
    in_func = 0
    cur_len = 0
  }
  /^[[:space:]]*$/ { if (in_func) cur_len++; next }
  {
    match($0, /^[[:space:]]*/)
    ws = RLENGTH
    if (in_func) {
      if (ws > decl_indent) {
        cur_len++
      } else {
        flush()
      }
    }
    if ($0 ~ /^[[:space:]]*(function[[:space:]]+[A-Za-z_]|def[[:space:]]+[A-Za-z_]|func[[:space:]]+\(?[A-Za-z_]|fn[[:space:]]+[A-Za-z_])/) {
      flush()
      decl_indent = ws
      in_func = 1
      cur_len = 0
    }
  }
  END { flush(); print max_len+0 }
' "$F")

printf '%s\t%d\t%d\t%d\t%d\n' "$F" "$LINES" "$FUNCS" "$MAX_FUNC_LEN" "$MAX_DEPTH"
