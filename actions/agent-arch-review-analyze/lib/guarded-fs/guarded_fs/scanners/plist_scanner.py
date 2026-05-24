"""plist scanner.

- Parses with plistlib (stdlib).
- Reports invalid UTF-8 (for XML plists).
- Reports suspicious Unicode in keys.
"""

from __future__ import annotations

import plistlib
import unicodedata

from .common import Finding, SEVERITY_BLOCK, SEVERITY_SUSPICIOUS

GRAMMAR = "plist"


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
        parsed = plistlib.loads(data)
    except plistlib.InvalidFileException as e:
        findings.append(
            Finding(
                severity=SEVERITY_BLOCK,
                reason="plist_parse_error",
                grammar=GRAMMAR,
                detail="plist parse error: " + str(e),
            )
        )
        return findings, {"parsed": False}
    except Exception as e:  # noqa: BLE001
        findings.append(
            Finding(
                severity=SEVERITY_BLOCK,
                reason="plist_parse_error",
                grammar=GRAMMAR,
                detail="plist parse exception: " + type(e).__name__ + ": " + str(e),
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
                    reason="plist_" + reason,
                    grammar=GRAMMAR,
                    detail="plist key " + dotted + " contains a suspicious codepoint",
                )
            )

    return findings, {"parsed": True}
