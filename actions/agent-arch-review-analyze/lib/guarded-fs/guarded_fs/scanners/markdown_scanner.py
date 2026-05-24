"""Markdown scanner.

Rejects / flags:
- unbalanced code fences (odd number of fence tokens).
- nested fences (a triple-backtick line inside a triple-backtick block).
- shell code blocks (```sh or ```bash or ```zsh) containing smart
  punctuation, leading-hash comments, or other shell scanner hits.
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
from . import shell_scanner

GRAMMAR = "markdown"


# A fence is three or more backticks at the start of a line, optionally
# followed by an info string.
FENCE_LINE = re.compile(rb"^(```+)([^\n]*)$", re.MULTILINE)


def _iter_blocks(data: bytes):
    """Yield (start_offset, end_offset, info_string) for each fenced
    code block. start_offset is just AFTER the opening fence line's
    newline; end_offset is just BEFORE the closing fence line."""
    fences = list(FENCE_LINE.finditer(data))
    i = 0
    while i + 1 < len(fences):
        open_m = fences[i]
        close_m = fences[i + 1]
        # Require fence-token length match: ``` opens a ``` block; ````
        # opens a ```` block. Mismatch means the block isn't closed by
        # the next candidate.
        if len(open_m.group(1)) != len(close_m.group(1)):
            # Hunt forward for a matching close.
            j = i + 2
            while j < len(fences) and len(fences[j].group(1)) != len(
                open_m.group(1)
            ):
                j += 1
            if j >= len(fences):
                # No close; nothing more to do.
                return
            close_m = fences[j]
            i = j + 1
        else:
            i += 2
        # Range between the opening fence line and the closing fence line.
        body_start = open_m.end() + 1  # +1 for the newline after the fence
        body_end = close_m.start()
        info = open_m.group(2).strip()
        yield (body_start, body_end, info, open_m.start(), close_m.start())


def scan(data: bytes, **_unused) -> tuple[list[Finding], dict]:
    findings: list[Finding] = []

    fences = list(FENCE_LINE.finditer(data))
    if len(fences) % 2 != 0:
        last = fences[-1]
        off = last.start()
        line, col = offset_to_line_column(data, off)
        findings.append(
            Finding(
                severity=SEVERITY_BLOCK,
                reason="markdown_unbalanced_fence",
                grammar=GRAMMAR,
                byte_offset=off,
                line=line,
                column=col,
                detail="odd number of code-fence tokens ({}); fences unbalanced".format(
                    len(fences)
                ),
                context=visible_byte_context(data, off),
            )
        )

    # Nested fence detection: scan each block body for `^```` lines.
    NESTED = re.compile(rb"^```", re.MULTILINE)
    block_count = 0
    shell_block_count = 0
    for body_start, body_end, info, _open_off, _close_off in _iter_blocks(data):
        block_count += 1
        body = data[body_start:body_end]
        # Nested-fence check on the body, NOT counting the closing
        # fence itself (which is at body_end, outside this slice).
        for n in NESTED.finditer(body):
            off = body_start + n.start()
            line, col = offset_to_line_column(data, off)
            findings.append(
                Finding(
                    severity=SEVERITY_BLOCK,
                    reason="markdown_nested_fence",
                    grammar=GRAMMAR,
                    byte_offset=off,
                    line=line,
                    column=col,
                    detail="triple-backtick inside a fenced block; this breaks rendering",
                    context=visible_byte_context(data, off),
                )
            )

        info_lower = info.lower()
        if info_lower in (b"sh", b"bash", b"zsh", b"shell"):
            shell_block_count += 1
            sub_findings, _ = shell_scanner.scan(body)
            for f in sub_findings:
                # Re-anchor the sub-finding's byte offset to global file.
                if f.byte_offset >= 0:
                    f.byte_offset = body_start + f.byte_offset
                    f.line, f.column = offset_to_line_column(data, f.byte_offset)
                    f.context = visible_byte_context(data, f.byte_offset)
                f.grammar = "markdown:shell"
                findings.append(f)

    return findings, {
        "fence_tokens": len(fences),
        "blocks": block_count,
        "shell_blocks": shell_block_count,
    }
