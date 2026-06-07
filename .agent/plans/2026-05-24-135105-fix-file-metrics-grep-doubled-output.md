---
name: fix-file-metrics-grep-doubled-output
status: in_progress
created: 2026-05-24T13:51:05Z
branch: feat/agent-architecture-review
pr: 45
blast_radius: low
---

# Fix file-metrics.sh crash on minimal/non-code files

## Problem

`actions/agent-arch-review-analyze/scripts/file-metrics.sh` crashes on minimal files (e.g. `printf 'hello\n' > x.md`) with:

```
line 84: printf: 0\n0: invalid number
```

Because `run-all.sh` uses `set -euo pipefail`, this crash kills the whole orchestrator and drops every analyzer scheduled to run after file-metrics.

## Root cause

Line 38:
```bash
FUNCS=$(grep -cE '...regex...' "$F" 2>/dev/null || echo 0)
```

When the regex matches zero lines:
- `grep -c` prints `0` to stdout (it always prints a count)
- `grep -c` exits with status 1 (no matches found)
- The `||` triggers, `echo 0` appends another `0` to stdout
- `FUNCS` becomes the string `"0\n0"` (two lines)
- `printf '%s\t%d\t%d\t%d\t%d\n'` chokes on `"0\n0"` as `%d`

(The user's hypothesis was that the awk subscripts above line 84 lacked an END default, but they all already `print ...+0`. The bug is the grep, not the awk.)

## Fix

1. Replace `|| echo 0` with `|| true` on line 38. `grep -c` already prints `0` - we just need to swallow its exit code.
2. Add belt-and-suspenders defaults right before the `printf` on line 84:
   `LINES=${LINES:-0}; FUNCS=${FUNCS:-0}; MAX_FUNC_LEN=${MAX_FUNC_LEN:-0}; MAX_DEPTH=${MAX_DEPTH:-0}`

## Verification

Reproduce the crash, apply the fix, re-run, expect a single tab-separated line with `1\t0\t0\t0`.

Also test on:
- empty file (0 bytes)
- a file with only comments
- a real source file (e.g. one of the scripts in this repo) to make sure the regular path still emits sane numbers

## Deliverable

One commit on `feat/agent-architecture-review` (PR #45 already open against `main`). No new PR.

## Out of scope

- Do NOT touch `byte-scan.sh`, `run-all.sh`'s byte-scan ordering, or any guarded-fs code.
- Do NOT refactor the analyzer beyond this fix.
