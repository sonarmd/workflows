"""YAML scanner.

If PyYAML is installed, parse and walk the document.
If not, return a single info-severity finding noting the skip.
"""

from __future__ import annotations

import unicodedata

from .common import Finding, SEVERITY_INFO, SEVERITY_SUSPICIOUS, SEVERITY_BLOCK

GRAMMAR = "yaml"

try:
    import yaml  # type: ignore

    _HAS_YAML = True
except ImportError:
    _HAS_YAML = False


def _walk_keys(node, path: str):
    if isinstance(node, dict):
        for k, v in node.items():
            yield (k, path + "." + str(k))
            yield from _walk_keys(v, path + "." + str(k))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from _walk_keys(v, path + "[" + str(i) + "]")


def _key_is_suspicious(key) -> str | None:
    if not isinstance(key, str):
        return None
    for ch in key:
        cat = unicodedata.category(ch)
        if cat in {"Cc", "Cf", "Co", "Cs", "Cn"}:
            return "suspicious_unicode_in_key:U+{:04X}".format(ord(ch))
    return None


def scan(data: bytes, **_unused) -> tuple[list[Finding], dict]:
    findings: list[Finding] = []
    if not _HAS_YAML:
        findings.append(
            Finding(
                severity=SEVERITY_INFO,
                reason="yaml_parse_skipped",
                grammar=GRAMMAR,
                detail="PyYAML not installed; YAML parse check skipped",
            )
        )
        return findings, {"parsed": False, "reason": "no_pyyaml"}

    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        findings.append(
            Finding(
                severity=SEVERITY_BLOCK,
                reason="yaml_invalid_utf8",
                grammar=GRAMMAR,
                detail="YAML bytes are not valid UTF-8",
            )
        )
        return findings, {"parsed": False}

    try:
        parsed = yaml.safe_load(text)
    except yaml.YAMLError as e:
        findings.append(
            Finding(
                severity=SEVERITY_BLOCK,
                reason="yaml_parse_error",
                grammar=GRAMMAR,
                detail="YAML parse error: " + str(e),
            )
        )
        return findings, {"parsed": False}

    for key, dotted in _walk_keys(parsed, "$"):
        reason = _key_is_suspicious(key)
        if reason:
            findings.append(
                Finding(
                    severity=SEVERITY_SUSPICIOUS,
                    reason="yaml_" + reason,
                    grammar=GRAMMAR,
                    detail="YAML key " + dotted + " contains a suspicious codepoint",
                )
            )

    return findings, {"parsed": True}
