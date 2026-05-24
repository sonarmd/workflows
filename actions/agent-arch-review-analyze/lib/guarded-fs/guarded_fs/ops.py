"""Guarded operations: safe_read, safe_write, safe_edit, safe_exec,
scan_path, render_check.

Every function:
- enforces allowed_roots / symlink-escape rejection (read + write only).
- returns a JSON-serializable dict envelope.
- writes an audit record.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path
from typing import Any, Iterable

from .audit import AuditLog
from .policy import Policy
from .scanners import REGISTRY, infer_grammar, scan_with
from .scanners.common import (
    Finding,
    STATUS_BINARY,
    STATUS_BLOCKED,
    STATUS_CLEAN,
    STATUS_INVALID_UTF8,
    STATUS_SKIPPED,
    STATUS_SUSPICIOUS,
    sha256_hex,
    status_from_findings,
)


WRITE_MODES = ("strict_block", "warn")


def _resolve(path: str) -> tuple[str, str]:
    """Return (path-as-passed, realpath). Does NOT require existence."""
    p = os.fspath(path)
    try:
        rp = os.path.realpath(p)
    except OSError:
        rp = p
    return p, rp


def _root_check(realpath: str, policy: Policy) -> dict | None:
    """Return an error envelope dict if the realpath escapes allowed
    roots, else None."""
    if policy.within_allowed_root(realpath):
        return None
    return {
        "status": "blocked",
        "reason": "outside_allowed_roots",
        "realpath": realpath,
        "allowed_roots": list(policy.allowed_roots),
    }


def _findings_to_dicts(findings: Iterable[Finding]) -> list[dict]:
    return [f.to_dict() for f in findings]


def _classify_envelope_status(
    findings: list[Finding], stats: dict
) -> str:
    if stats.get("is_binaryish") and any(
        f.reason == "invalid_utf8" for f in findings
    ):
        return STATUS_BINARY
    if any(f.reason == "invalid_utf8" for f in findings):
        return STATUS_INVALID_UTF8
    return status_from_findings(findings)


def _annotate_content_for_model(
    data: bytes, findings: list[Finding]
) -> str:
    """Return a model-safe rendering of the bytes.

    Suspicious bytes are wrapped in [reason:U+XXXX] markers so the
    model sees they were there. We do NOT silently strip them.

    For invalid_utf8: returns the bytes with errors='replace' and adds
    [invalid_utf8@N] markers at each bad-byte position.
    """
    # Sort findings by byte_offset (only ones with a real offset).
    anchored = [f for f in findings if f.byte_offset >= 0]
    if not anchored:
        return data.decode("utf-8", errors="replace")

    out: list[str] = []
    cursor = 0
    for f in sorted(anchored, key=lambda x: x.byte_offset):
        off = f.byte_offset
        if off < cursor:
            continue
        out.append(data[cursor:off].decode("utf-8", errors="replace"))
        if f.reason == "invalid_utf8":
            out.append("[invalid_utf8@" + str(off) + "]")
            cursor = off + 1
        else:
            # Find the end of the character at off (1..4 bytes UTF-8).
            try:
                ch_end = off + len(
                    bytes(data[off : off + 4]).decode("utf-8")[0].encode("utf-8")
                )
            except UnicodeDecodeError:
                ch_end = off + 1
            cp = f.codepoint or "U+????"
            out.append("[" + f.reason + ":" + cp + "]")
            cursor = ch_end
    out.append(data[cursor:].decode("utf-8", errors="replace"))
    return "".join(out)


def _new_audit_id_envelope(envelope: dict, audit_id: str) -> dict:
    envelope["audit_id"] = audit_id
    return envelope


# --------------------------------------------------------------------
# safe_read
# --------------------------------------------------------------------

def safe_read(
    path: str,
    grammar: str | None = None,
    policy: Policy | None = None,
) -> dict:
    p, rp = _resolve(path)
    policy = policy or Policy()
    audit = AuditLog()

    err = _root_check(rp, policy)
    if err is not None:
        audit_id = audit.record(
            operation="safe_read",
            path=p,
            realpath=rp,
            grammar=grammar,
            status="blocked",
            file_changed=False,
            findings=[],
            verification={"reason": "outside_allowed_roots"},
        )
        return _new_audit_id_envelope(
            {
                "status": "blocked",
                "file_changed": False,
                "path": p,
                "realpath": rp,
                "grammar": grammar,
                "content_for_model": "",
                "findings": [],
                "verification": err,
            },
            audit_id,
        )

    if not os.path.exists(rp):
        audit_id = audit.record(
            operation="safe_read",
            path=p,
            realpath=rp,
            grammar=grammar,
            status="blocked",
            file_changed=False,
            findings=[],
            verification={"reason": "not_found"},
        )
        return _new_audit_id_envelope(
            {
                "status": "blocked",
                "file_changed": False,
                "path": p,
                "realpath": rp,
                "grammar": grammar,
                "content_for_model": "",
                "findings": [],
                "verification": {"reason": "not_found"},
            },
            audit_id,
        )

    with open(rp, "rb") as f:
        data = f.read()

    grammar = grammar or infer_grammar(rp)
    findings, stats = scan_with(
        grammar, data, forbidden_codepoints=policy.forbidden_codepoints
    )
    status = _classify_envelope_status(findings, stats)
    content_for_model = (
        "" if stats.get("is_binaryish") and len(data) > 65536
        else _annotate_content_for_model(data, findings)
    )

    verification = {
        "scan_stats": stats,
        "is_binaryish": stats.get("is_binaryish", False),
    }
    audit_id = audit.record(
        operation="safe_read",
        path=p,
        realpath=rp,
        grammar=grammar,
        status=status,
        file_changed=False,
        findings=_findings_to_dicts(findings),
        verification=verification,
        old_sha256=sha256_hex(data),
    )
    return _new_audit_id_envelope(
        {
            "status": status,
            "file_changed": False,
            "path": p,
            "realpath": rp,
            "grammar": grammar,
            "content_for_model": content_for_model,
            "findings": _findings_to_dicts(findings),
            "verification": verification,
        },
        audit_id,
    )


# --------------------------------------------------------------------
# safe_write
# --------------------------------------------------------------------

def _atomic_write(path: str, content: bytes) -> str:
    """Write content to path via temp+fsync+rename. Returns sha256 of
    the bytes actually written, AFTER a re-read."""
    parent = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(parent, exist_ok=True)
    fd, tmp = tempfile.mkstemp(
        prefix="." + os.path.basename(path) + ".",
        suffix=".tmp",
        dir=parent,
    )
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        # fsync parent for durable rename.
        try:
            dfd = os.open(parent, os.O_DIRECTORY)
            try:
                os.fsync(dfd)
            finally:
                os.close(dfd)
        except OSError:
            pass
        os.rename(tmp, path)
        # Re-read.
        with open(path, "rb") as f:
            actual = f.read()
        return sha256_hex(actual)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def safe_write(
    path: str,
    content: bytes | str,
    grammar: str | None = None,
    mode: str = "strict_block",
    policy: Policy | None = None,
) -> dict:
    if mode not in WRITE_MODES:
        raise ValueError("mode must be one of " + ", ".join(WRITE_MODES))

    p, rp = _resolve(path)
    policy = policy or Policy()
    audit = AuditLog()

    if isinstance(content, str):
        content_bytes = content.encode("utf-8")
    else:
        content_bytes = bytes(content)

    err = _root_check(rp, policy)
    if err is not None:
        audit_id = audit.record(
            operation="safe_write",
            path=p,
            realpath=rp,
            grammar=grammar,
            status="blocked",
            file_changed=False,
            findings=[],
            verification={"reason": "outside_allowed_roots"},
        )
        return _new_audit_id_envelope(
            {
                "status": "blocked",
                "file_changed": False,
                "path": p,
                "realpath": rp,
                "grammar": grammar,
                "findings": [],
                "verification": err,
                "diff_summary": {},
                "backup_path": None,
            },
            audit_id,
        )

    grammar = grammar or infer_grammar(rp)
    findings, stats = scan_with(
        grammar, content_bytes, forbidden_codepoints=policy.forbidden_codepoints
    )
    proposed_status = _classify_envelope_status(findings, stats)

    is_sensitive = policy.is_sensitive(rp)
    should_block = mode == "strict_block" and proposed_status != STATUS_CLEAN
    if is_sensitive and proposed_status != STATUS_CLEAN:
        should_block = True

    if should_block:
        audit_id = audit.record(
            operation="safe_write",
            path=p,
            realpath=rp,
            grammar=grammar,
            status=STATUS_BLOCKED,
            file_changed=False,
            findings=_findings_to_dicts(findings),
            verification={
                "reason": "scanner_rejected",
                "proposed_status": proposed_status,
            },
        )
        return _new_audit_id_envelope(
            {
                "status": STATUS_BLOCKED,
                "file_changed": False,
                "path": p,
                "realpath": rp,
                "grammar": grammar,
                "findings": _findings_to_dicts(findings),
                "verification": {
                    "reason": "scanner_rejected",
                    "proposed_status": proposed_status,
                },
                "diff_summary": {},
                "backup_path": None,
            },
            audit_id,
        )

    old_sha = None
    if os.path.exists(rp):
        with open(rp, "rb") as f:
            old_bytes = f.read()
        old_sha = sha256_hex(old_bytes)

    new_sha = _atomic_write(rp, content_bytes)

    # Re-scan after write.
    with open(rp, "rb") as f:
        after_bytes = f.read()
    after_findings, after_stats = scan_with(
        grammar, after_bytes, forbidden_codepoints=policy.forbidden_codepoints
    )
    after_status = _classify_envelope_status(after_findings, after_stats)

    verification = {
        "sha256_matches": new_sha == sha256_hex(content_bytes),
        "rescan_status": after_status,
        "rescan_findings_count": len(after_findings),
    }
    audit_id = audit.record(
        operation="safe_write",
        path=p,
        realpath=rp,
        grammar=grammar,
        status=after_status,
        file_changed=True,
        findings=_findings_to_dicts(after_findings),
        verification=verification,
        old_sha256=old_sha,
        new_sha256=new_sha,
    )
    return _new_audit_id_envelope(
        {
            "status": after_status,
            "file_changed": True,
            "path": p,
            "realpath": rp,
            "grammar": grammar,
            "findings": _findings_to_dicts(after_findings),
            "verification": verification,
            "diff_summary": {
                "old_sha256": old_sha,
                "new_sha256": new_sha,
                "old_bytes": len(old_bytes) if old_sha else 0,
                "new_bytes": len(content_bytes),
            },
            "backup_path": None,
        },
        audit_id,
    )


# --------------------------------------------------------------------
# safe_edit
# --------------------------------------------------------------------

def safe_edit(
    path: str,
    old: str | bytes,
    new: str | bytes,
    grammar: str | None = None,
    policy: Policy | None = None,
) -> dict:
    p, rp = _resolve(path)
    policy = policy or Policy()
    audit = AuditLog()

    err = _root_check(rp, policy)
    if err is not None:
        audit_id = audit.record(
            operation="safe_edit",
            path=p,
            realpath=rp,
            grammar=grammar,
            status="blocked",
            file_changed=False,
            findings=[],
            verification={"reason": "outside_allowed_roots"},
        )
        return _new_audit_id_envelope(
            {
                "status": "blocked",
                "file_changed": False,
                "path": p,
                "realpath": rp,
                "grammar": grammar,
                "findings": [],
                "verification": err,
                "diff_summary": {},
                "backup_path": None,
            },
            audit_id,
        )

    if not os.path.exists(rp):
        audit_id = audit.record(
            operation="safe_edit",
            path=p,
            realpath=rp,
            grammar=grammar,
            status="blocked",
            file_changed=False,
            findings=[],
            verification={"reason": "not_found"},
        )
        return _new_audit_id_envelope(
            {
                "status": "blocked",
                "file_changed": False,
                "path": p,
                "realpath": rp,
                "grammar": grammar,
                "findings": [],
                "verification": {"reason": "not_found"},
                "diff_summary": {},
                "backup_path": None,
            },
            audit_id,
        )

    with open(rp, "rb") as f:
        existing = f.read()
    existing_text = existing.decode("utf-8", errors="replace")

    if isinstance(old, bytes):
        old_str = old.decode("utf-8", errors="replace")
    else:
        old_str = old
    if isinstance(new, bytes):
        new_str = new.decode("utf-8", errors="replace")
    else:
        new_str = new

    count = existing_text.count(old_str)
    if count == 0:
        audit_id = audit.record(
            operation="safe_edit",
            path=p,
            realpath=rp,
            grammar=grammar,
            status="blocked",
            file_changed=False,
            findings=[],
            verification={"reason": "old_not_found", "match_count": 0},
        )
        return _new_audit_id_envelope(
            {
                "status": "blocked",
                "file_changed": False,
                "path": p,
                "realpath": rp,
                "grammar": grammar,
                "findings": [],
                "verification": {"reason": "old_not_found", "match_count": 0},
                "diff_summary": {},
                "backup_path": None,
            },
            audit_id,
        )
    if count > 1:
        audit_id = audit.record(
            operation="safe_edit",
            path=p,
            realpath=rp,
            grammar=grammar,
            status="blocked",
            file_changed=False,
            findings=[],
            verification={"reason": "old_ambiguous", "match_count": count},
        )
        return _new_audit_id_envelope(
            {
                "status": "blocked",
                "file_changed": False,
                "path": p,
                "realpath": rp,
                "grammar": grammar,
                "findings": [],
                "verification": {"reason": "old_ambiguous", "match_count": count},
                "diff_summary": {},
                "backup_path": None,
            },
            audit_id,
        )

    proposed = existing_text.replace(old_str, new_str, 1)
    return safe_write(rp, proposed, grammar=grammar, policy=policy)


# --------------------------------------------------------------------
# safe_exec
# --------------------------------------------------------------------

def _git_status(args: list[str]) -> dict:
    cp = subprocess.run(
        ["git", "status", "--porcelain"] + args,
        capture_output=True,
        text=True,
        check=False,
    )
    return {"stdout": cp.stdout, "stderr": cp.stderr, "returncode": cp.returncode}


def _git_diff(args: list[str]) -> dict:
    cp = subprocess.run(
        ["git", "diff"] + args,
        capture_output=True,
        text=True,
        check=False,
    )
    return {"stdout": cp.stdout, "stderr": cp.stderr, "returncode": cp.returncode}


def _zsh_parse(args: list[str]) -> dict:
    if not args:
        return {"stdout": "", "stderr": "missing file path", "returncode": 2}
    cp = subprocess.run(
        ["zsh", "-n", args[0]], capture_output=True, text=True, check=False
    )
    return {"stdout": cp.stdout, "stderr": cp.stderr, "returncode": cp.returncode}


def _bash_parse(args: list[str]) -> dict:
    if not args:
        return {"stdout": "", "stderr": "missing file path", "returncode": 2}
    cp = subprocess.run(
        ["bash", "-n", args[0]], capture_output=True, text=True, check=False
    )
    return {"stdout": cp.stdout, "stderr": cp.stderr, "returncode": cp.returncode}


def _render_man(args: list[str]) -> dict:
    if not args:
        return {"stdout": "", "stderr": "missing file path", "returncode": 2}
    src = args[0]
    # Pipe man -P cat -l SRC through col -b for clean text.
    p1 = subprocess.run(
        ["man", "-P", "cat", "-l", src], capture_output=True, check=False
    )
    p2 = subprocess.run(
        ["col", "-b"], input=p1.stdout, capture_output=True, check=False
    )
    return {
        "stdout": p2.stdout.decode("utf-8", errors="replace"),
        "stderr": (p1.stderr + p2.stderr).decode("utf-8", errors="replace"),
        "returncode": p2.returncode if p2.returncode else p1.returncode,
    }


def _scan_path_exec(args: list[str]) -> dict:
    if not args:
        return {"stdout": "", "stderr": "missing path", "returncode": 2}
    res = scan_path(args[0], grammar=args[1] if len(args) > 1 else None)
    return {
        "stdout": json.dumps(res, ensure_ascii=False, indent=2),
        "stderr": "",
        "returncode": 0,
    }


def _run_tests(args: list[str]) -> dict:
    target = args[0] if args else "tools/guarded-fs/tests"
    cp = subprocess.run(
        ["python3", "-m", "unittest", "discover", target, "-v"],
        capture_output=True,
        text=True,
        check=False,
    )
    return {"stdout": cp.stdout, "stderr": cp.stderr, "returncode": cp.returncode}


COMMAND_REGISTRY = {
    "git_status": _git_status,
    "git_diff": _git_diff,
    "zsh_parse": _zsh_parse,
    "bash_parse": _bash_parse,
    "render_man": _render_man,
    "scan_path": _scan_path_exec,
    "run_tests": _run_tests,
}


def safe_exec(command_id: str, args: list[str] | None = None) -> dict:
    args = args or []
    audit = AuditLog()
    fn = COMMAND_REGISTRY.get(command_id)
    if fn is None:
        audit_id = audit.record(
            operation="safe_exec",
            path=None,
            realpath=None,
            grammar=None,
            status="blocked",
            file_changed=False,
            verification={"reason": "unknown_command_id", "command_id": command_id},
        )
        return {
            "status": "blocked",
            "file_changed": False,
            "command_id": command_id,
            "verification": {"reason": "unknown_command_id"},
            "audit_id": audit_id,
        }
    result = fn(list(args))
    status = STATUS_CLEAN if result.get("returncode", 1) == 0 else "exec_nonzero"
    audit_id = audit.record(
        operation="safe_exec",
        path=None,
        realpath=None,
        grammar=None,
        status=status,
        file_changed=False,
        verification={"command_id": command_id, "returncode": result.get("returncode")},
    )
    return {
        "status": status,
        "file_changed": False,
        "command_id": command_id,
        "args": list(args),
        "result": result,
        "audit_id": audit_id,
    }


# --------------------------------------------------------------------
# scan_path
# --------------------------------------------------------------------

def scan_path(
    path: str,
    grammar: str | None = None,
    policy: Policy | None = None,
) -> dict:
    p, rp = _resolve(path)
    policy = policy or Policy()
    audit = AuditLog()

    if not os.path.exists(rp):
        audit_id = audit.record(
            operation="scan_path",
            path=p,
            realpath=rp,
            grammar=grammar,
            status="blocked",
            file_changed=False,
            verification={"reason": "not_found"},
        )
        return {
            "status": "blocked",
            "file_changed": False,
            "path": p,
            "realpath": rp,
            "verification": {"reason": "not_found"},
            "audit_id": audit_id,
        }

    if os.path.isfile(rp):
        if policy.is_binary_skip(rp):
            audit_id = audit.record(
                operation="scan_path",
                path=p,
                realpath=rp,
                grammar=grammar,
                status=STATUS_SKIPPED,
                file_changed=False,
                verification={"reason": "binary_skip_glob"},
            )
            return {
                "status": STATUS_SKIPPED,
                "file_changed": False,
                "path": p,
                "realpath": rp,
                "grammar": grammar,
                "findings": [],
                "verification": {"reason": "binary_skip_glob"},
                "audit_id": audit_id,
            }

        with open(rp, "rb") as f:
            data = f.read()
        grammar = grammar or infer_grammar(rp)
        findings, stats = scan_with(
            grammar, data, forbidden_codepoints=policy.forbidden_codepoints
        )
        status = _classify_envelope_status(findings, stats)
        audit_id = audit.record(
            operation="scan_path",
            path=p,
            realpath=rp,
            grammar=grammar,
            status=status,
            file_changed=False,
            findings=_findings_to_dicts(findings),
            verification={"scan_stats": stats},
        )
        return {
            "status": status,
            "file_changed": False,
            "path": p,
            "realpath": rp,
            "grammar": grammar,
            "findings": _findings_to_dicts(findings),
            "verification": {"scan_stats": stats},
            "audit_id": audit_id,
        }

    # Directory: walk and scan each file. Aggregate.
    per_file: list[dict] = []
    worst = STATUS_CLEAN
    severity_order = {
        STATUS_CLEAN: 0,
        STATUS_SKIPPED: 0,
        STATUS_SUSPICIOUS: 1,
        STATUS_BINARY: 2,
        STATUS_INVALID_UTF8: 3,
        STATUS_BLOCKED: 4,
    }
    for root, dirs, files in os.walk(rp):
        # Don't recurse into the .guard audit dir or .git.
        dirs[:] = [d for d in dirs if d not in (".guard", ".git", "node_modules")]
        for fn in sorted(files):
            full = os.path.join(root, fn)
            if policy.is_binary_skip(full):
                continue
            with open(full, "rb") as f:
                data = f.read()
            g = grammar or infer_grammar(full)
            findings, stats = scan_with(
                g, data, forbidden_codepoints=policy.forbidden_codepoints
            )
            st = _classify_envelope_status(findings, stats)
            per_file.append(
                {
                    "path": os.path.relpath(full, rp),
                    "grammar": g,
                    "status": st,
                    "findings_count": len(findings),
                    "findings": _findings_to_dicts(findings)[:50],
                }
            )
            if severity_order.get(st, 0) > severity_order.get(worst, 0):
                worst = st

    audit_id = audit.record(
        operation="scan_path",
        path=p,
        realpath=rp,
        grammar=grammar,
        status=worst,
        file_changed=False,
        verification={"files_scanned": len(per_file)},
    )
    return {
        "status": worst,
        "file_changed": False,
        "path": p,
        "realpath": rp,
        "grammar": grammar,
        "summary": {
            "files_scanned": len(per_file),
            "files_with_findings": sum(1 for r in per_file if r["findings_count"] > 0),
        },
        "files": per_file,
        "audit_id": audit_id,
    }


# --------------------------------------------------------------------
# render_check
# --------------------------------------------------------------------

def render_check(path: str, grammar: str | None = None, policy: Policy | None = None) -> dict:
    """For roff manpages, scan source then render via man + col -b and
    scan the output for forbidden bytes / unintended acute accents.
    """
    p, rp = _resolve(path)
    policy = policy or Policy()
    audit = AuditLog()

    if not os.path.exists(rp):
        audit_id = audit.record(
            operation="render_check",
            path=p,
            realpath=rp,
            grammar=grammar,
            status="blocked",
            file_changed=False,
            verification={"reason": "not_found"},
        )
        return {
            "status": "blocked",
            "file_changed": False,
            "path": p,
            "realpath": rp,
            "verification": {"reason": "not_found"},
            "audit_id": audit_id,
        }

    g = grammar or infer_grammar(rp) or "byte"

    with open(rp, "rb") as f:
        src = f.read()
    src_findings, src_stats = scan_with(
        g, src, forbidden_codepoints=policy.forbidden_codepoints
    )
    src_status = _classify_envelope_status(src_findings, src_stats)

    rendered_status = "skipped"
    rendered_findings_dicts: list[dict] = []
    rendered_text = ""
    if g == "roff":
        if shutil.which("man"):
            p1 = subprocess.run(
                ["man", "-P", "cat", "-l", rp], capture_output=True, check=False
            )
            p2 = subprocess.run(
                ["col", "-b"], input=p1.stdout, capture_output=True, check=False
            )
            rendered = p2.stdout
            rendered_text = rendered.decode("utf-8", errors="replace")
        elif shutil.which("groff"):
            p1 = subprocess.run(
                ["groff", "-man", "-Tutf8", rp], capture_output=True, check=False
            )
            p2 = subprocess.run(
                ["col", "-b"], input=p1.stdout, capture_output=True, check=False
            )
            rendered = p2.stdout
            rendered_text = rendered.decode("utf-8", errors="replace")
        else:
            rendered = b""

        if rendered:
            r_findings, r_stats = scan_with(
                "byte",
                rendered,
                forbidden_codepoints=policy.forbidden_codepoints,
            )
            rendered_status = _classify_envelope_status(r_findings, r_stats)
            rendered_findings_dicts = _findings_to_dicts(r_findings)

    # Worst-of: source vs rendered.
    if src_status == STATUS_BLOCKED or rendered_status == STATUS_BLOCKED:
        overall = STATUS_BLOCKED
    elif src_status == STATUS_INVALID_UTF8 or rendered_status == STATUS_INVALID_UTF8:
        overall = STATUS_INVALID_UTF8
    elif src_status == STATUS_SUSPICIOUS or rendered_status == STATUS_SUSPICIOUS:
        overall = STATUS_SUSPICIOUS
    else:
        overall = STATUS_CLEAN

    audit_id = audit.record(
        operation="render_check",
        path=p,
        realpath=rp,
        grammar=g,
        status=overall,
        file_changed=False,
        verification={
            "source_status": src_status,
            "rendered_status": rendered_status,
            "rendered_bytes": len(rendered_text.encode("utf-8")),
        },
    )
    return {
        "status": overall,
        "file_changed": False,
        "path": p,
        "realpath": rp,
        "grammar": g,
        "source_findings": _findings_to_dicts(src_findings),
        "rendered_findings": rendered_findings_dicts,
        "rendered_excerpt": rendered_text[:2000],
        "verification": {
            "source_status": src_status,
            "rendered_status": rendered_status,
        },
        "audit_id": audit_id,
    }
