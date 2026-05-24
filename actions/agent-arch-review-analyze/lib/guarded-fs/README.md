# guarded-fs

Guarded filesystem operations for AI agents. Wraps reads, writes, edits,
and a small allowlist of commands behind a multi-grammar scanner so that
unsafe bytes, grammar violations, hidden characters, binary content,
invalid UTF-8, roff escape misuse, shell parse risk, and Markdown fence
breakage fail loudly instead of being silently ignored or auto-fixed.

The byte scanner is a refactor of the existing `command/cleanse` script,
preserving its capabilities and adding real byte offsets, structured
findings, and policy-driven forbidden codepoints.

## What it does

- safe_read: realpath + allowed-roots check, byte+grammar scan, return
  an annotated content_for_model that never hides suspicious bytes.
- safe_write: scan proposed bytes; reject loudly on sensitive grammars;
  write atomically (temp + fsync + rename); re-read and re-scan.
- safe_edit: exact-match replacement, rejects zero or multiple matches,
  routes the proposed full content through safe_write.
- safe_exec: allowlisted command IDs only, no raw shell, shell=False.
- scan_path: scan one file or a directory tree; skip known binary junk.
- render_check: for roff manpages, scan source and also scan the
  output of man -P cat -l SRC piped through col -b.

Every operation emits a JSON envelope and writes a record to
.guard/audit.jsonl with timestamp, audit_id, hashes, findings count,
and verification fields.

## CLI usage

The CLI script is `bin/guarded-fs`. It is executable and self-contained
(no install step required). All output is JSON.

  bin/guarded-fs scan PATH [--grammar G] [--policy P]
  bin/guarded-fs read PATH [--grammar G] [--policy P]
  bin/guarded-fs write PATH --content-file FILE [--grammar G] [--mode M] [--policy P]
  bin/guarded-fs edit PATH --old-file OLD --new-file NEW [--grammar G] [--policy P]
  bin/guarded-fs exec COMMAND_ID JSON_ARGS
  bin/guarded-fs render-check PATH [--grammar G] [--policy P]

Allowed command IDs for `exec`:
  git_status, git_diff, zsh_parse, bash_parse, render_man, scan_path,
  run_tests.

## MCP usage

  python3 -m guarded_fs.mcp_server

Exposes the six operations as MCP tools under server name `guarded_fs`.
Expected Claude tool names:

  mcp__guarded_fs__safe_read
  mcp__guarded_fs__safe_write
  mcp__guarded_fs__safe_edit
  mcp__guarded_fs__safe_exec
  mcp__guarded_fs__scan_path
  mcp__guarded_fs__render_check

If the `mcp` SDK is not installed, the server exits with status 2 and a
JSON line describing the missing dependency. The CLI is unaffected.

## settings.json deny strategy

The intended consumer-side pattern: a Claude Code hook denies direct
Read / Write / Edit / MultiEdit / Bash-read / Bash-write on
`protected_paths`. Agents must route those operations through the
MCP tools. The hook is out of scope for this package; settings.json
edits are not performed here. The package only provides the safe
substitutes.

## Fail-loud behavior

- Unsafe writes to sensitive paths return status=blocked and do not
  touch the target file.
- Reads with suspicious bytes return status=suspicious with the
  bytes annotated inline (never stripped).
- Invalid UTF-8 returns status=invalid_utf8 with real byte offsets of
  every bad byte.
- Outside-allowed-roots is a flat reject with reason=outside_allowed_roots.
- Unknown safe_exec command IDs are a flat reject.

## Tests

  python3 -m unittest discover tools/guarded-fs/tests -v

Uses stdlib unittest only; no pip dependencies.

## Policy

See `policy.example.json`. Pass with `--policy PATH` on any CLI command.
If no policy is given, defaults apply: empty allowed_roots (all paths
allowed for read/scan; writes still scanned), the spec's forbidden
codepoint set, and a generous binary_skip_globs list.
