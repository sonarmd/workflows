"""guarded-fs: paranoid filesystem operations for AI agents.

Public API:
    safe_read(path, grammar=None) -> dict
    safe_write(path, content, grammar=None, mode='strict_block') -> dict
    safe_edit(path, old, new, grammar=None) -> dict
    safe_exec(command_id, args) -> dict
    scan_path(path, grammar=None) -> dict
    render_check(path, grammar=None) -> dict
"""

from .ops import (
    safe_read,
    safe_write,
    safe_edit,
    safe_exec,
    scan_path,
    render_check,
)

__all__ = [
    "safe_read",
    "safe_write",
    "safe_edit",
    "safe_exec",
    "scan_path",
    "render_check",
]
