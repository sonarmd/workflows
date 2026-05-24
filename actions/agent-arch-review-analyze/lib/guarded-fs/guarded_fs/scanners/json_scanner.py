"""JSON scanner.

- Parses with the stdlib json module.
- Reports invalid UTF-8 (delegated to byte scanner; here we only catch
  high-level parse errors).
- Reports suspicious Unicode in keys: any control / format / private-use
  / surrogate character in a top-level or nested JSON object key.
"""

from __future__ import annotations

import json
import unicodedata

from .common import Finding, SEVERITY_BLOCK, SEVERITY_SUSPICIOUS, offset_to_line_column

GRAMMAR = "json"


def _walk_keys(node, path: str):
    if isinstance(node, dict):
        for k, v in node.items():
            yield (k, path + "." + str(k))
            yield from _walk_keys(v, path + "." + str(k))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from _walk_keys(v, path + "[" + str(i) + "]")


def _key_is_suspicious(key: str) -> str | None:
    for ch in key:
        cat = unicodedata.category(ch)
        if cat in {"Cc", "Cf", "Co", "Cs", "Cn"}:
            return "suspicious_unicode_in_key:U+{:04X}".format(ord(ch))
    return None


def scan(data: bytes, **_unused) -> tuple[list[Finding], dict]:
    findings: list[Finding] = []
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as e:
        findings.append(
            Finding(
                severity=SEVERITY_BLOCK,
                reason="json_invalid_utf8",
                grammar=GRAMMAR,
                byte_offset=e.start,
                detail="JSON bytes are not valid UTF-8",
            )
        )
        return findings, {"parsed": False}

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as e:
        # Approximate the byte offset from the character position.
        off = len(text[: e.pos].encode("utf-8"))
        line, col = offset_to_line_column(data, off)
        findings.append(
            Finding(
                severity=SEVERITY_BLOCK,
                reason="json_parse_error",
                grammar=GRAMMAR,
                byte_offset=off,
                line=line,
                column=col,
                detail="JSON parse error: " + e.msg,
            )
        )
        return findings, {"parsed": False}

    for key, dotted in _walk_keys(parsed, "$"):
        if not isinstance(key, str):
            continue
        reason = _key_is_suspicious(key)
        if reason:
            findings.append(
                Finding(
                    severity=SEVERITY_SUSPICIOUS,
                    reason="json_" + reason,
                    grammar=GRAMMAR,
                    detail="JSON key " + dotted + " contains a suspicious codepoint",
                )
            )

    return findings, {"parsed": True}
