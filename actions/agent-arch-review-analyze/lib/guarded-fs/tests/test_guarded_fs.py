"""Integration tests for guarded-fs.

Every required case from the prompt has its own test. Uses stdlib
unittest so the test suite has zero pip dependencies. The package
itself is made importable via conftest.py (sys.path insertion).
"""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

# Ensure the package is importable when tests are discovered from any cwd.
import conftest  # noqa: F401  (side-effect: sys.path insertion)

from guarded_fs import (
    safe_edit,
    safe_exec,
    safe_read,
    safe_write,
    scan_path,
)
from guarded_fs.policy import Policy
from guarded_fs.scanners import scan_with


# --------------------------------------------------------------------
# Test helpers
# --------------------------------------------------------------------

class TmpRoot:
    """Sandbox directory + policy that allows only that dir."""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix="guarded-fs-test-")
        self.policy = Policy(allowed_roots=[self.dir])

    def path(self, name: str) -> str:
        return os.path.join(self.dir, name)

    def write_raw(self, name: str, data: bytes) -> str:
        p = self.path(name)
        with open(p, "wb") as f:
            f.write(data)
        return p

    def cleanup(self) -> None:
        import shutil

        shutil.rmtree(self.dir, ignore_errors=True)


# --------------------------------------------------------------------
# Scanner-level tests (1..9, 15)
# --------------------------------------------------------------------

class TestScanners(unittest.TestCase):

    # 1. roff backslash-apostrophe s is rejected.
    def test_roff_bs_apos_rejected(self):
        body = b".TH FOO 1\nTony\\'s widget\n"
        findings, _ = scan_with("roff", body)
        reasons = [f.reason for f in findings]
        self.assertIn("roff_bs_apos", reasons)

    # 2. U+00B4 (ACUTE ACCENT) is rejected.
    def test_acute_accent_rejected(self):
        body = "before ´ after".encode("utf-8")
        findings, _ = scan_with("byte", body)
        self.assertTrue(any(f.reason == "acute_accent" for f in findings))

    # 3. U+2014 (EM DASH) is rejected in sensitive files.
    def test_em_dash_blocked_in_sensitive(self):
        t = TmpRoot()
        try:
            policy = Policy(
                allowed_roots=[t.dir],
                sensitive_globs=["*.sh"],
            )
            path = t.path("victim.sh")
            content = "echo a — b\n"
            res = safe_write(path, content, grammar="byte", mode="strict_block", policy=policy)
            self.assertEqual(res["status"], "blocked")
            self.assertFalse(os.path.exists(path))
        finally:
            t.cleanup()

    # 4. NBSP (U+00A0) is rejected.
    def test_nbsp_rejected(self):
        body = "hello world".encode("utf-8")
        findings, _ = scan_with("byte", body)
        self.assertTrue(any(f.reason == "nbsp" for f in findings))

    # 5. ZERO WIDTH SPACE (U+200B) is rejected.
    def test_zws_rejected(self):
        body = "a​b".encode("utf-8")
        findings, _ = scan_with("byte", body)
        self.assertTrue(any(f.reason == "zero_width" for f in findings))

    # 6. Literal backspace (U+0008) is rejected.
    def test_backspace_rejected(self):
        body = b"a\x08b"
        findings, _ = scan_with("byte", body)
        self.assertTrue(any(f.reason == "backspace" for f in findings))

    # 7. .DS_Store is classified binary or skipped.
    def test_ds_store_skipped(self):
        t = TmpRoot()
        try:
            ds = t.write_raw(".DS_Store", b"\x00\x00\x00\x01Bud1" + b"\x00" * 32)
            res = scan_path(ds, policy=t.policy)
            self.assertIn(res["status"], ("skipped", "binary"))
        finally:
            t.cleanup()

    # 8. Markdown nested fence failure is detected.
    def test_markdown_nested_fence(self):
        body = b"```sh\nsome code\n```\nstill in block\n```\n"
        findings, _ = scan_with("markdown", body)
        reasons = [f.reason for f in findings]
        self.assertTrue(
            "markdown_nested_fence" in reasons
            or "markdown_unbalanced_fence" in reasons
        )

    # 9. Shell PATH clobber is detected.
    def test_shell_path_clobber(self):
        body = b'export PATH="/opt/bin:/usr/bin"\n'
        findings, _ = scan_with("shell", body)
        self.assertTrue(any(f.reason == "shell_path_clobber" for f in findings))

    # 15. Invalid UTF-8 is reported without losing byte evidence.
    def test_invalid_utf8_byte_evidence(self):
        # \xc3\x28 is a classic invalid UTF-8 sequence (C3 expects a
        # continuation byte; 28 is '(' which is not one).
        body = b"hello \xc3\x28 there"
        findings, _ = scan_with("byte", body)
        bad = [f for f in findings if f.reason == "invalid_utf8"]
        self.assertGreaterEqual(len(bad), 1)
        # Real byte offsets, not approximations.
        for f in bad:
            self.assertGreaterEqual(f.byte_offset, 0)
            self.assertEqual(f.grammar, "byte")
            self.assertIn("0x", f.detail)


# --------------------------------------------------------------------
# safe_edit tests (10, 11)
# --------------------------------------------------------------------

class TestSafeEdit(unittest.TestCase):

    # 10. safe_edit rejects zero matches.
    def test_edit_zero_matches_rejected(self):
        t = TmpRoot()
        try:
            p = t.write_raw("a.txt", b"hello world\n")
            res = safe_edit(p, "nope", "yep", grammar="byte", policy=t.policy)
            self.assertEqual(res["status"], "blocked")
            self.assertEqual(res["verification"]["reason"], "old_not_found")
            with open(p, "rb") as f:
                self.assertEqual(f.read(), b"hello world\n")
        finally:
            t.cleanup()

    # 11. safe_edit rejects multiple matches.
    def test_edit_multi_match_rejected(self):
        t = TmpRoot()
        try:
            p = t.write_raw("a.txt", b"foo foo foo\n")
            res = safe_edit(p, "foo", "bar", grammar="byte", policy=t.policy)
            self.assertEqual(res["status"], "blocked")
            self.assertEqual(res["verification"]["reason"], "old_ambiguous")
            self.assertEqual(res["verification"]["match_count"], 3)
            with open(p, "rb") as f:
                self.assertEqual(f.read(), b"foo foo foo\n")
        finally:
            t.cleanup()


# --------------------------------------------------------------------
# safe_write tests (12, 13)
# --------------------------------------------------------------------

class TestSafeWrite(unittest.TestCase):

    # 12. safe_write does NOT modify the file on rejected content.
    def test_write_rejected_no_modify(self):
        t = TmpRoot()
        try:
            p = t.path("victim.sh")
            # Pre-populate with clean known content.
            with open(p, "wb") as f:
                f.write(b"echo OK\n")
            policy = Policy(allowed_roots=[t.dir], sensitive_globs=["*.sh"])
            bad = "echo —\n"  # EM DASH forbidden codepoint
            res = safe_write(p, bad, grammar="byte", mode="strict_block", policy=policy)
            self.assertEqual(res["status"], "blocked")
            self.assertFalse(res["file_changed"])
            with open(p, "rb") as f:
                self.assertEqual(f.read(), b"echo OK\n")
        finally:
            t.cleanup()

    # 13. safe_write writes atomically on clean content.
    def test_write_atomic_clean(self):
        t = TmpRoot()
        try:
            p = t.path("a.txt")
            res = safe_write(p, b"hello clean world\n", grammar="byte", policy=t.policy)
            self.assertEqual(res["status"], "clean")
            self.assertTrue(res["file_changed"])
            with open(p, "rb") as f:
                self.assertEqual(f.read(), b"hello clean world\n")
            # No leftover temp files in the dir.
            stragglers = [
                fn for fn in os.listdir(t.dir)
                if fn.startswith(".") and fn.endswith(".tmp")
            ]
            self.assertEqual(stragglers, [])
        finally:
            t.cleanup()


# --------------------------------------------------------------------
# safe_exec tests (14)
# --------------------------------------------------------------------

class TestSafeExec(unittest.TestCase):

    # 14. safe_exec rejects unknown command_id.
    def test_exec_unknown_id(self):
        res = safe_exec("nonexistent_command", [])
        self.assertEqual(res["status"], "blocked")
        self.assertEqual(res["verification"]["reason"], "unknown_command_id")

    # Bonus: known IDs at least dispatch (no assertion on output, just
    # that we get a structured envelope back).
    def test_exec_known_id_dispatches(self):
        res = safe_exec("git_status", [])
        self.assertIn("result", res)
        self.assertIn("returncode", res["result"])


# --------------------------------------------------------------------
# Symlink-escape and allowed-roots boundary
# --------------------------------------------------------------------

class TestBoundary(unittest.TestCase):

    def test_outside_allowed_roots_read_blocked(self):
        t = TmpRoot()
        try:
            other = tempfile.mkdtemp(prefix="guarded-fs-other-")
            try:
                bad = os.path.join(other, "x.txt")
                with open(bad, "wb") as f:
                    f.write(b"hi")
                res = safe_read(bad, grammar="byte", policy=t.policy)
                self.assertEqual(res["status"], "blocked")
                self.assertEqual(res["verification"]["reason"], "outside_allowed_roots")
            finally:
                import shutil

                shutil.rmtree(other, ignore_errors=True)
        finally:
            t.cleanup()


if __name__ == "__main__":
    unittest.main()
