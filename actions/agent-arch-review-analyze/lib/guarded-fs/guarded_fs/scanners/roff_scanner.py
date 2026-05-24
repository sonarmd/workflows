"""Roff / manpage scanner.

Rejects:
- backslash-apostrophe in normal text (\\' produces a U+00B4 acute accent
  when rendered, almost never what the author intends in plain text).
- literal backspace bytes (terminal-paste contamination).
- copied terminal overstrike sequences (char BS char patterns from
  captured `man | col` output that survived round-trips).

Render-check (called by ops.render_check, not by scan()):
- render through `man -P cat` or `groff -man -Tutf8` then pipe through
  `col -b`, scan the output for forbidden bytes / unintended U+00B4.
"""

from __future__ import annotations

import re

from .common import (
    Finding,
    SEVERITY_BLOCK,
    SEVERITY_SUSPICIOUS,
    offset_to_line_column,
    visible_byte_context,
)

GRAMMAR = "roff"


# A backslash-apostrophe in roff means "start a comment that ends at
# end of line" in some contexts; in body text it is almost always an
# author mistake that renders as a stray acute accent.
BS_APOS_BODY = re.compile(rb"\\'", re.MULTILINE)


# Terminal overstrike pattern: any byte, BS (0x08), the same byte again.
OVERSTRIKE = re.compile(rb"(.)\x08\1")


def scan(data: bytes, **_unused) -> tuple[list[Finding], dict]:
    findings: list[Finding] = []

    for match in BS_APOS_BODY.finditer(data):
        off = match.start()
        line, col = offset_to_line_column(data, off)
        findings.append(
            Finding(
                severity=SEVERITY_BLOCK,
                reason="roff_bs_apos",
                grammar=GRAMMAR,
                byte_offset=off,
                line=line,
                column=col,
                detail="backslash-apostrophe in roff source; renders as U+00B4 acute accent",
                context=visible_byte_context(data, off),
            )
        )

    for match in OVERSTRIKE.finditer(data):
        off = match.start()
        line, col = offset_to_line_column(data, off)
        findings.append(
            Finding(
                severity=SEVERITY_BLOCK,
                reason="roff_overstrike",
                grammar=GRAMMAR,
                byte_offset=off,
                line=line,
                column=col,
                detail="captured terminal overstrike (char BS char) detected; paste from `man` not `man | col -b`",
                context=visible_byte_context(data, off),
            )
        )

    # Standalone backspace bytes (not in overstrike position) are still
    # bad. We let the byte_scanner flag them as 'backspace' / forbidden
    # codepoint U+0008, so no duplicate report here.

    return findings, {"checked_patterns": 2}
