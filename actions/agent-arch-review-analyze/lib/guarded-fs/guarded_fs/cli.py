"""guarded-fs CLI.

All commands write JSON to stdout. Errors write a JSON envelope with
status=error and exit non-zero.

Subcommands:
    scan PATH [--grammar G] [--policy P]
    read PATH [--grammar G] [--policy P]
    write PATH --content-file FILE [--grammar G] [--mode strict_block|warn] [--policy P]
    edit PATH --old-file OLD --new-file NEW [--grammar G] [--policy P]
    exec COMMAND_ID [--] ARGS_JSON
    render-check PATH [--grammar G] [--policy P]
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from .ops import (
    render_check,
    safe_edit,
    safe_exec,
    safe_read,
    safe_write,
    scan_path,
)
from .policy import Policy


def _emit(obj: Any) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False, indent=2))
    sys.stdout.write("\n")


def _load_policy(p: str | None) -> Policy:
    return Policy.load(p)


def cmd_scan(args: argparse.Namespace) -> int:
    res = scan_path(
        args.path, grammar=args.grammar, policy=_load_policy(args.policy)
    )
    _emit(res)
    return 0 if res.get("status") in ("clean", "skipped") else 1


def cmd_read(args: argparse.Namespace) -> int:
    res = safe_read(
        args.path, grammar=args.grammar, policy=_load_policy(args.policy)
    )
    _emit(res)
    return 0 if res.get("status") in ("clean", "suspicious") else 1


def cmd_write(args: argparse.Namespace) -> int:
    with open(args.content_file, "rb") as f:
        content = f.read()
    res = safe_write(
        args.path,
        content,
        grammar=args.grammar,
        mode=args.mode,
        policy=_load_policy(args.policy),
    )
    _emit(res)
    return 0 if res.get("status") in ("clean", "suspicious") else 1


def cmd_edit(args: argparse.Namespace) -> int:
    with open(args.old_file, "rb") as f:
        old = f.read()
    with open(args.new_file, "rb") as f:
        new = f.read()
    res = safe_edit(
        args.path,
        old,
        new,
        grammar=args.grammar,
        policy=_load_policy(args.policy),
    )
    _emit(res)
    return 0 if res.get("status") in ("clean", "suspicious") else 1


def cmd_exec(args: argparse.Namespace) -> int:
    raw = args.json_args or "[]"
    try:
        a = json.loads(raw)
    except json.JSONDecodeError as e:
        _emit({"status": "error", "reason": "args_not_json", "detail": str(e)})
        return 2
    if not isinstance(a, list):
        _emit({"status": "error", "reason": "args_must_be_list"})
        return 2
    res = safe_exec(args.command_id, [str(x) for x in a])
    _emit(res)
    return 0 if res.get("status") == "clean" else 1


def cmd_render_check(args: argparse.Namespace) -> int:
    res = render_check(
        args.path, grammar=args.grammar, policy=_load_policy(args.policy)
    )
    _emit(res)
    return 0 if res.get("status") in ("clean", "suspicious", "skipped") else 1


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="guarded-fs")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("scan", help="Scan a file or directory")
    s.add_argument("path")
    s.add_argument("--grammar")
    s.add_argument("--policy")
    s.set_defaults(func=cmd_scan)

    r = sub.add_parser("read", help="Guarded read of a file")
    r.add_argument("path")
    r.add_argument("--grammar")
    r.add_argument("--policy")
    r.set_defaults(func=cmd_read)

    w = sub.add_parser("write", help="Guarded atomic write")
    w.add_argument("path")
    w.add_argument("--content-file", required=True)
    w.add_argument("--grammar")
    w.add_argument("--mode", default="strict_block", choices=["strict_block", "warn"])
    w.add_argument("--policy")
    w.set_defaults(func=cmd_write)

    e = sub.add_parser("edit", help="Guarded exact replacement edit")
    e.add_argument("path")
    e.add_argument("--old-file", required=True)
    e.add_argument("--new-file", required=True)
    e.add_argument("--grammar")
    e.add_argument("--policy")
    e.set_defaults(func=cmd_edit)

    x = sub.add_parser("exec", help="Run an allowlisted command by id")
    x.add_argument("command_id")
    x.add_argument("json_args", nargs="?", default="[]")
    x.set_defaults(func=cmd_exec)

    rc = sub.add_parser("render-check", help="Render-check a file (roff)")
    rc.add_argument("path")
    rc.add_argument("--grammar")
    rc.add_argument("--policy")
    rc.set_defaults(func=cmd_render_check)

    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
