"""Scanner registry and dispatch.

Each grammar module exposes a `scan(data: bytes, ...)` function and a
module-level `GRAMMAR` string. The registry maps a grammar name to its
scan callable.
"""

from __future__ import annotations

from typing import Callable, Optional

from . import (
    byte_scanner,
    json_scanner,
    markdown_scanner,
    plist_scanner,
    roff_scanner,
    shell_scanner,
    yaml_scanner,
)
from .common import Finding

ScanCallable = Callable[..., tuple[list[Finding], dict]]

REGISTRY: dict[str, ScanCallable] = {
    "byte": byte_scanner.scan,
    "roff": roff_scanner.scan,
    "shell": shell_scanner.scan,
    "markdown": markdown_scanner.scan,
    "json": json_scanner.scan,
    "plist": plist_scanner.scan,
    "yaml": yaml_scanner.scan,
}


GRAMMAR_BY_SUFFIX: dict[str, str] = {
    ".sh": "shell",
    ".bash": "shell",
    ".zsh": "shell",
    ".md": "markdown",
    ".markdown": "markdown",
    ".json": "json",
    ".plist": "plist",
    ".yaml": "yaml",
    ".yml": "yaml",
    ".1": "roff",
    ".2": "roff",
    ".3": "roff",
    ".4": "roff",
    ".5": "roff",
    ".6": "roff",
    ".7": "roff",
    ".8": "roff",
    ".man": "roff",
}


def infer_grammar(path: str) -> Optional[str]:
    """Best-effort grammar guess from filename. None means 'byte only'."""
    lower = path.lower()
    for suffix, name in GRAMMAR_BY_SUFFIX.items():
        if lower.endswith(suffix):
            return name
    return None


def scan_with(
    grammar: Optional[str],
    data: bytes,
    *,
    forbidden_codepoints=None,
) -> tuple[list[Finding], dict]:
    """Run the byte scanner unconditionally; if grammar is set, also
    run the grammar scanner and merge findings.

    Byte findings come first.
    """
    findings, stats = byte_scanner.scan(
        data, forbidden_codepoints=forbidden_codepoints
    )
    if grammar and grammar != "byte":
        scanner = REGISTRY.get(grammar)
        if scanner is None:
            return findings, stats
        g_findings, g_stats = scanner(data)
        findings.extend(g_findings)
        stats["grammar_stats"] = g_stats
    return findings, stats
