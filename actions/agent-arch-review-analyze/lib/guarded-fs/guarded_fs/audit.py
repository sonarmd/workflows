"""Audit log writer.

Each guarded operation appends a single JSON object as one line to
.guard/audit.jsonl. The path is relative to the guarded-fs package
root by default but can be overridden via the GUARDED_FS_AUDIT env var.

The writer:
- creates the .guard directory if missing.
- never logs full file contents. Bodies inside Finding objects are
  already bounded to small context windows by the scanners; here we
  additionally redact obvious secret-shaped strings before persisting.
"""

from __future__ import annotations

import json
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path


# Heuristic patterns for secret-shaped strings. We do NOT try to be
# exhaustive (the secret-sniffer hook is the real defense). This is
# belt-and-suspenders for audit-log hygiene only.
SECRET_PATTERNS = [
    re.compile(r"[A-Za-z0-9+/]{40,}={0,2}"),       # long base64-ish
    re.compile(r"[A-Fa-f0-9]{40,}"),                # long hex
    re.compile(r"(?:sk|pk|tok|api|sec|key)[-_][A-Za-z0-9]{16,}"),
]


def _default_audit_path() -> Path:
    here = Path(__file__).resolve().parent.parent
    p = Path(os.environ.get("GUARDED_FS_AUDIT", str(here / ".guard" / "audit.jsonl")))
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def _redact(s: str) -> str:
    out = s
    for pat in SECRET_PATTERNS:
        out = pat.sub("[REDACTED]", out)
    return out


def _redact_finding(f: dict) -> dict:
    g = dict(f)
    for k in ("detail", "context"):
        v = g.get(k)
        if isinstance(v, str):
            g[k] = _redact(v)
    return g


class AuditLog:
    def __init__(self, path: Path | None = None):
        self.path = path or _default_audit_path()

    def record(
        self,
        *,
        operation: str,
        path: str | None,
        realpath: str | None,
        grammar: str | None,
        status: str,
        file_changed: bool,
        findings: list[dict] | None = None,
        verification: dict | None = None,
        old_sha256: str | None = None,
        new_sha256: str | None = None,
        extra: dict | None = None,
    ) -> str:
        rec = {
            "timestamp": datetime.now(timezone.utc)
            .isoformat(timespec="seconds")
            .replace("+00:00", "Z"),
            "audit_id": str(uuid.uuid4()),
            "operation": operation,
            "path": path,
            "realpath": realpath,
            "grammar": grammar,
            "status": status,
            "file_changed": file_changed,
            "findings_count": len(findings or []),
            "verification": verification or {},
        }
        if old_sha256:
            rec["old_sha256"] = old_sha256
        if new_sha256:
            rec["new_sha256"] = new_sha256
        if extra:
            rec["extra"] = extra
        line = json.dumps(rec, ensure_ascii=False)
        with self.path.open("a", encoding="utf-8") as f:
            f.write(line + "\n")
        return rec["audit_id"]
