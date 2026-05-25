"""Byte / Unicode scanner.

Ported from command/cleanse with three changes:
1. Returns structured Finding objects, not free-form events.
2. Real byte offsets (not approximated post-decode). For valid UTF-8
   input we decode incrementally so each character knows the byte index
   it started at. For invalid UTF-8 we report the exact byte position
   of every malformed sequence.
3. Honors a policy-supplied forbidden_codepoints set in addition to
   the always-bad classes (Cc / Cs / Co / Cn except whitelist).
"""

from __future__ import annotations

import unicodedata
from typing import Iterable, Optional

from .common import (
    Finding,
    SEVERITY_BLOCK,
    SEVERITY_INFO,
    SEVERITY_SUSPICIOUS,
    byte_stats,
    offset_to_line_column,
    visible_byte_context,
)


GRAMMAR = "byte"


BIDI_CONTROL_NAMES = {
    "LEFT-TO-RIGHT MARK",
    "RIGHT-TO-LEFT MARK",
    "LEFT-TO-RIGHT EMBEDDING",
    "RIGHT-TO-LEFT EMBEDDING",
    "POP DIRECTIONAL FORMATTING",
    "LEFT-TO-RIGHT OVERRIDE",
    "RIGHT-TO-LEFT OVERRIDE",
    "LEFT-TO-RIGHT ISOLATE",
    "RIGHT-TO-LEFT ISOLATE",
    "FIRST STRONG ISOLATE",
    "POP DIRECTIONAL ISOLATE",
}

ZERO_WIDTH_NAMES = {
    "ZERO WIDTH SPACE",
    "ZERO WIDTH NON-JOINER",
    "ZERO WIDTH JOINER",
    "ZERO WIDTH NO-BREAK SPACE",
    "WORD JOINER",
}


# Default forbidden codepoints per spec. Policy may override.
DEFAULT_FORBIDDEN_CODEPOINTS = frozenset(
    {
        0x0008,  # BACKSPACE
        0x001B,  # ESCAPE
        0x00A0,  # NO-BREAK SPACE
        0x00B4,  # ACUTE ACCENT
        0x200B,  # ZERO WIDTH SPACE
        0x200C,  # ZERO WIDTH NON-JOINER
        0x200D,  # ZERO WIDTH JOINER
        0x2018,  # LEFT SINGLE QUOTE
        0x2019,  # RIGHT SINGLE QUOTE
        0x201C,  # LEFT DOUBLE QUOTE
        0x201D,  # RIGHT DOUBLE QUOTE
        0x2013,  # EN DASH
        0x2014,  # EM DASH
        0x2212,  # MINUS SIGN
    }
)


def char_reason(ch: str) -> Optional[str]:
    """Same classification as cleanse, with a stable reason string."""
    if ch in "\n\r\t":
        return None

    if ch == "\x08":
        return "backspace"
    if ch == "\x1b":
        return "escape"

    cat = unicodedata.category(ch)
    name = unicodedata.name(ch, "UNKNOWN")

    if cat == "Cf":
        if name in BIDI_CONTROL_NAMES:
            return "bidi_control"
        if name in ZERO_WIDTH_NAMES or "ZERO WIDTH" in name:
            return "zero_width"
        if "VARIATION SELECTOR" in name:
            return "variation_selector"
        return "format_control"

    if cat in {"Cc", "Cs", "Co", "Cn"}:
        return "unicode_category_" + cat

    code = ord(ch)
    if 0xFDD0 <= code <= 0xFDEF or code & 0xFFFE == 0xFFFE:
        return "unicode_noncharacter"

    return None


def reason_for_forbidden_codepoint(code: int) -> str:
    """Stable, code-friendly reason name for a forbidden codepoint."""
    table = {
        0x0008: "backspace",
        0x001B: "escape",
        0x00A0: "nbsp",
        0x00B4: "acute_accent",
        0x200B: "zero_width",
        0x200C: "zero_width",
        0x200D: "zero_width",
        0x2018: "smart_quote_left_single",
        0x2019: "smart_quote_right_single",
        0x201C: "smart_quote_left_double",
        0x201D: "smart_quote_right_double",
        0x2013: "en_dash",
        0x2014: "em_dash",
        0x2212: "minus_sign",
    }
    return table.get(code, "forbidden_codepoint_U+{:04X}".format(code))


def _utf8_char_offsets(data: bytes) -> Iterable[tuple[int, str]]:
    """Yield (byte_offset, character) pairs by incrementally decoding.

    For each valid character, the byte_offset is the index in `data`
    where the character's first byte sits. Invalid sequences are NOT
    yielded by this function; they are reported separately by
    _utf8_invalid_offsets().
    """
    i = 0
    decoder_input = memoryview(data)
    while i < len(decoder_input):
        b = decoder_input[i]
        # Determine expected byte length by leading-byte pattern.
        if b < 0x80:
            length = 1
        elif b < 0xC2:
            # Continuation byte or overlong start; skip.
            i += 1
            continue
        elif b < 0xE0:
            length = 2
        elif b < 0xF0:
            length = 3
        elif b < 0xF5:
            length = 4
        else:
            i += 1
            continue

        if i + length > len(decoder_input):
            i += 1
            continue

        chunk = bytes(decoder_input[i : i + length])
        try:
            ch = chunk.decode("utf-8")
        except UnicodeDecodeError:
            i += 1
            continue
        yield (i, ch)
        i += length


def _utf8_invalid_offsets(data: bytes) -> list[int]:
    """Return byte offsets of every byte that is NOT part of a valid
    UTF-8 sequence.

    We decode `data` incrementally. On each UnicodeDecodeError we record
    every byte in the offending range, advance past it, and continue.
    """
    bad: list[int] = []
    i = 0
    while i < len(data):
        try:
            data[i:].decode("utf-8")
            break
        except UnicodeDecodeError as e:
            start = i + e.start
            end = i + e.end
            for k in range(start, end):
                bad.append(k)
            i = end
            if i <= start:
                i = start + 1
    return bad


def scan(
    data: bytes,
    *,
    forbidden_codepoints: Optional[Iterable[int]] = None,
    max_findings: int = 1000,
    binary_nul_ratio: float = 0.005,
    binary_control_ratio: float = 0.02,
) -> tuple[list[Finding], dict]:
    """Scan raw bytes. Returns (findings, stats).

    stats is the byte_stats dict plus a derived "is_binaryish" flag.
    Findings are byte-anchored where possible.
    """
    forbidden = set(DEFAULT_FORBIDDEN_CODEPOINTS)
    if forbidden_codepoints is not None:
        forbidden = set(forbidden_codepoints)

    findings: list[Finding] = []
    stats = byte_stats(data)
    is_binaryish = (
        stats["nul_ratio"] >= binary_nul_ratio
        or stats["control_ratio"] >= binary_control_ratio
    )
    stats["is_binaryish"] = is_binaryish

    # Invalid UTF-8 bytes (real offsets).
    invalid_offsets = _utf8_invalid_offsets(data)
    for off in invalid_offsets[:max_findings]:
        line, col = offset_to_line_column(data, off)
        findings.append(
            Finding(
                severity=SEVERITY_BLOCK,
                reason="invalid_utf8",
                grammar=GRAMMAR,
                byte_offset=off,
                line=line,
                column=col,
                detail="byte 0x{:02x} not part of a valid UTF-8 sequence".format(
                    data[off]
                ),
                context=visible_byte_context(data, off),
            )
        )
    if len(invalid_offsets) > max_findings:
        findings.append(
            Finding(
                severity=SEVERITY_INFO,
                reason="event_limit_reached",
                grammar=GRAMMAR,
                detail="suppressed {} additional invalid_utf8 events".format(
                    len(invalid_offsets) - max_findings
                ),
            )
        )

    # Character-level findings: walk valid UTF-8 chars by byte offset.
    char_count = 0
    for off, ch in _utf8_char_offsets(data):
        if char_count >= max_findings:
            break
        code = ord(ch)
        cp = "U+{:04X}".format(code)
        name = unicodedata.name(ch, "UNKNOWN")
        cat = unicodedata.category(ch)

        reason: Optional[str] = None
        severity: Optional[str] = None

        if code in forbidden:
            reason = reason_for_forbidden_codepoint(code)
            severity = SEVERITY_BLOCK
        else:
            r = char_reason(ch)
            if r is not None:
                reason = r
                severity = SEVERITY_SUSPICIOUS

        if reason is None:
            continue

        line, col = offset_to_line_column(data, off)
        findings.append(
            Finding(
                severity=severity or SEVERITY_SUSPICIOUS,
                reason=reason,
                grammar=GRAMMAR,
                byte_offset=off,
                line=line,
                column=col,
                codepoint=cp,
                unicode_name=name,
                category=cat,
                detail="codepoint " + cp + " at byte " + str(off),
                context=visible_byte_context(data, off),
            )
        )
        char_count += 1

    return findings, stats
