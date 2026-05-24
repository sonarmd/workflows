"""Common types and helpers for guarded-fs scanners.

Plain ASCII only. The whole point of guarded-fs is to be paranoid about
non-ASCII content; we keep our own source ASCII so the dogfooding scan
of this package does not flag the package itself.
"""

from __future__ import annotations

import hashlib
from dataclasses import asdict, dataclass
from typing import Any


SEVERITY_CLEAN = "clean"
SEVERITY_INFO = "info"
SEVERITY_SUSPICIOUS = "suspicious"
SEVERITY_BLOCK = "block"


STATUS_CLEAN = "clean"
STATUS_SUSPICIOUS = "suspicious"
STATUS_BINARY = "binary"
STATUS_INVALID_UTF8 = "invalid_utf8"
STATUS_BLOCKED = "blocked"
STATUS_SKIPPED = "skipped"


@dataclass
class Finding:
    """A single scanner finding.

    severity: one of SEVERITY_*.
    reason: short stable string code (e.g. "zero_width", "roff_bs_apos").
    grammar: which scanner produced it (byte, roff, shell, markdown, ...).
    byte_offset: real byte offset into the scanned bytes when known. Use
        -1 when the finding is structural and has no byte position.
    line / column: 1-indexed; both default to 0 when unknown.
    codepoint: e.g. "U+200B" when applicable; empty string otherwise.
    unicode_name: e.g. "ZERO WIDTH SPACE"; empty when not applicable.
    category: Unicode category (e.g. "Cf") when applicable.
    detail: free-form short string for human reading.
    context: small visible-bytes window around the finding (best effort).
    """

    severity: str
    reason: str
    grammar: str
    byte_offset: int = -1
    line: int = 0
    column: int = 0
    codepoint: str = ""
    unicode_name: str = ""
    category: str = ""
    detail: str = ""
    context: str = ""

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def status_from_findings(findings: list[Finding]) -> str:
    """Reduce a list of findings to a single envelope status.

    block > suspicious > info > clean.
    """
    has_block = any(f.severity == SEVERITY_BLOCK for f in findings)
    if has_block:
        return STATUS_BLOCKED
    has_susp = any(f.severity == SEVERITY_SUSPICIOUS for f in findings)
    if has_susp:
        return STATUS_SUSPICIOUS
    return STATUS_CLEAN


def visible_byte_context(data: bytes, pos: int, radius: int = 96) -> str:
    """Render a small window of bytes around `pos` for human display.

    Bytes 32..126 inclusive are emitted verbatim; \\n \\r \\t get escape
    forms; everything else becomes \\xNN. Output is plain ASCII.
    """
    lo = max(0, pos - radius)
    hi = min(len(data), pos + radius)
    chunk = data[lo:hi]

    out: list[str] = []
    for b in chunk:
        if 32 <= b <= 126:
            out.append(chr(b))
        elif b == 10:
            out.append("\\n")
        elif b == 13:
            out.append("\\r")
        elif b == 9:
            out.append("\\t")
        else:
            out.append("\\x{:02x}".format(b))
    return "".join(out)


def offset_to_line_column(data: bytes, offset: int) -> tuple[int, int]:
    """Compute 1-indexed (line, column) for a byte offset.

    Counts \\n bytes up to `offset`. Cheap and correct for ASCII /
    UTF-8 input where line breaks are single bytes.
    """
    if offset < 0 or offset > len(data):
        return (0, 0)
    head = data[:offset]
    line = head.count(b"\n") + 1
    last_nl = head.rfind(b"\n")
    if last_nl == -1:
        column = offset + 1
    else:
        column = offset - last_nl
    return (line, column)


def byte_stats(data: bytes) -> dict[str, Any]:
    """Coarse byte stats, used for binary-ish detection."""
    n = len(data)
    controls = sum(1 for b in data if (b < 32 and b not in (9, 10, 13)) or b == 127)
    high = sum(1 for b in data if b > 127)
    nul = data.count(0)
    return {
        "bytes": n,
        "nul": nul,
        "esc": data.count(0x1B),
        "cr": data.count(0x0D),
        "controls": controls,
        "high": high,
        "nul_ratio": nul / max(n, 1),
        "control_ratio": controls / max(n, 1),
        "high_ratio": high / max(n, 1),
    }
