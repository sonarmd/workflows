"""guarded-fs MCP server.

Exposes safe_read, safe_write, safe_edit, safe_exec, scan_path,
render_check as tools under the server name `guarded_fs`.

If the `mcp` Python package is not installed, this module exits with
status 2 and a JSON line describing the missing dependency. We DO NOT
fall back to a stub server, per the spec.
"""

from __future__ import annotations

import json
import sys


def _missing(module: str) -> int:
    sys.stderr.write(
        json.dumps(
            {
                "status": "missing_dependency",
                "module": module,
                "install": "pip install mcp",
                "message": "guarded-fs MCP server requires the mcp SDK; the CLI is unaffected.",
            }
        )
        + "\n"
    )
    return 2


def main() -> int:
    try:
        from mcp.server import Server  # type: ignore
        from mcp.server.stdio import stdio_server  # type: ignore
        from mcp.types import Tool, TextContent  # type: ignore
    except ImportError:
        return _missing("mcp")

    from .ops import (
        safe_read,
        safe_write,
        safe_edit,
        safe_exec,
        scan_path,
        render_check,
    )

    server = Server("guarded_fs")

    @server.list_tools()  # type: ignore[misc]
    async def _list_tools() -> list[Tool]:
        return [
            Tool(
                name="safe_read",
                description="Guarded read of a file with scanner annotations.",
                inputSchema={
                    "type": "object",
                    "required": ["path"],
                    "properties": {
                        "path": {"type": "string"},
                        "grammar": {"type": ["string", "null"]},
                    },
                },
            ),
            Tool(
                name="safe_write",
                description="Guarded atomic write. Rejects unsafe content for sensitive grammars.",
                inputSchema={
                    "type": "object",
                    "required": ["path", "content"],
                    "properties": {
                        "path": {"type": "string"},
                        "content": {"type": "string"},
                        "grammar": {"type": ["string", "null"]},
                        "mode": {"type": "string", "enum": ["strict_block", "warn"]},
                    },
                },
            ),
            Tool(
                name="safe_edit",
                description="Guarded exact-match replacement edit.",
                inputSchema={
                    "type": "object",
                    "required": ["path", "old", "new"],
                    "properties": {
                        "path": {"type": "string"},
                        "old": {"type": "string"},
                        "new": {"type": "string"},
                        "grammar": {"type": ["string", "null"]},
                    },
                },
            ),
            Tool(
                name="safe_exec",
                description="Run an allowlisted command by id.",
                inputSchema={
                    "type": "object",
                    "required": ["command_id"],
                    "properties": {
                        "command_id": {"type": "string"},
                        "args": {"type": "array", "items": {"type": "string"}},
                    },
                },
            ),
            Tool(
                name="scan_path",
                description="Scan a file or directory; return findings.",
                inputSchema={
                    "type": "object",
                    "required": ["path"],
                    "properties": {
                        "path": {"type": "string"},
                        "grammar": {"type": ["string", "null"]},
                    },
                },
            ),
            Tool(
                name="render_check",
                description="Scan a file and (for roff) its rendered output.",
                inputSchema={
                    "type": "object",
                    "required": ["path"],
                    "properties": {
                        "path": {"type": "string"},
                        "grammar": {"type": ["string", "null"]},
                    },
                },
            ),
        ]

    @server.call_tool()  # type: ignore[misc]
    async def _call_tool(name: str, arguments: dict) -> list[TextContent]:
        if name == "safe_read":
            res = safe_read(arguments["path"], grammar=arguments.get("grammar"))
        elif name == "safe_write":
            res = safe_write(
                arguments["path"],
                arguments["content"],
                grammar=arguments.get("grammar"),
                mode=arguments.get("mode", "strict_block"),
            )
        elif name == "safe_edit":
            res = safe_edit(
                arguments["path"],
                arguments["old"],
                arguments["new"],
                grammar=arguments.get("grammar"),
            )
        elif name == "safe_exec":
            res = safe_exec(arguments["command_id"], arguments.get("args", []))
        elif name == "scan_path":
            res = scan_path(arguments["path"], grammar=arguments.get("grammar"))
        elif name == "render_check":
            res = render_check(arguments["path"], grammar=arguments.get("grammar"))
        else:
            res = {"status": "error", "reason": "unknown_tool", "name": name}
        return [TextContent(type="text", text=json.dumps(res, ensure_ascii=False))]

    import asyncio

    async def run() -> None:
        async with stdio_server() as (r, w):
            await server.run(r, w, server.create_initialization_options())

    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
