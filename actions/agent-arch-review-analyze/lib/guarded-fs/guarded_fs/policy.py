"""Policy loading + helpers.

A policy.json file controls:
- allowed_roots: filesystem roots within which all guarded operations
  must stay. Symlink escapes outside any allowed root are rejected.
- protected_paths: paths that must be accessed through guarded-fs even
  when they live inside an allowed root (informational; the actual
  enforcement is consumer-side, e.g. a Claude hook that blocks direct
  Read/Write/Edit on these paths).
- sensitive_globs: glob patterns whose grammar scanners run in strict
  mode (block on any suspicious finding).
- forbidden_codepoints: list of integer codepoints that any scan flags
  as blocking (overrides defaults).
- roff_forbidden_patterns: list of regex strings; the roff scanner adds
  one finding per match.
- shell_forbidden_patterns: list of regex strings; the shell scanner
  adds one finding per match.
- binary_skip_globs: glob patterns whose files are classified as binary
  and skipped during recursive scans by default.

If no policy file is supplied, DEFAULT_POLICY is used.
"""

from __future__ import annotations

import fnmatch
import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

from .scanners.byte_scanner import DEFAULT_FORBIDDEN_CODEPOINTS


DEFAULT_POLICY: dict = {
    "allowed_roots": [],
    "protected_paths": [],
    "sensitive_globs": [],
    "forbidden_codepoints": sorted(int(c) for c in DEFAULT_FORBIDDEN_CODEPOINTS),
    "roff_forbidden_patterns": [],
    "shell_forbidden_patterns": [],
    "binary_skip_globs": [
        ".DS_Store",
        "*.png",
        "*.jpg",
        "*.jpeg",
        "*.gif",
        "*.webp",
        "*.ico",
        "*.tiff",
        "*.bmp",
        "*.heic",
        "*.pdf",
        "*.zip",
        "*.tar",
        "*.tar.gz",
        "*.tgz",
        "*.gz",
        "*.bz2",
        "*.xz",
        "*.7z",
        "*.dmg",
        "*.iso",
        "*.so",
        "*.dylib",
        "*.dll",
        "*.a",
        "*.o",
        "*.pyc",
        "*.class",
        "*.jar",
        "*.wasm",
        "*.woff",
        "*.woff2",
        "*.ttf",
        "*.otf",
        "*.eot",
        "*.mp3",
        "*.mp4",
        "*.mov",
        "*.avi",
        "*.wav",
        "*.flac",
        "*.ogg",
    ],
}


@dataclass
class Policy:
    allowed_roots: list[str] = field(default_factory=list)
    protected_paths: list[str] = field(default_factory=list)
    sensitive_globs: list[str] = field(default_factory=list)
    forbidden_codepoints: frozenset[int] = field(
        default_factory=lambda: frozenset(DEFAULT_FORBIDDEN_CODEPOINTS)
    )
    roff_forbidden_patterns: list[str] = field(default_factory=list)
    shell_forbidden_patterns: list[str] = field(default_factory=list)
    binary_skip_globs: list[str] = field(
        default_factory=lambda: list(DEFAULT_POLICY["binary_skip_globs"])
    )

    @classmethod
    def from_dict(cls, raw: dict) -> "Policy":
        return cls(
            allowed_roots=list(raw.get("allowed_roots") or []),
            protected_paths=list(raw.get("protected_paths") or []),
            sensitive_globs=list(raw.get("sensitive_globs") or []),
            forbidden_codepoints=frozenset(
                int(c) for c in (raw.get("forbidden_codepoints") or [])
            ),
            roff_forbidden_patterns=list(raw.get("roff_forbidden_patterns") or []),
            shell_forbidden_patterns=list(
                raw.get("shell_forbidden_patterns") or []
            ),
            binary_skip_globs=list(raw.get("binary_skip_globs") or []),
        )

    @classmethod
    def load(cls, path: str | None) -> "Policy":
        if not path:
            return cls.from_dict(DEFAULT_POLICY)
        with open(path, "rb") as f:
            raw = json.loads(f.read().decode("utf-8"))
        return cls.from_dict(raw)

    def is_sensitive(self, path: str) -> bool:
        basename = os.path.basename(path)
        for g in self.sensitive_globs:
            if fnmatch.fnmatch(path, g) or fnmatch.fnmatch(basename, g):
                return True
        return False

    def is_binary_skip(self, path: str) -> bool:
        basename = os.path.basename(path)
        for g in self.binary_skip_globs:
            if fnmatch.fnmatch(basename, g) or fnmatch.fnmatch(path, g):
                return True
        return False

    def within_allowed_root(self, realpath: str) -> bool:
        if not self.allowed_roots:
            return True
        rp = os.path.realpath(realpath)
        for root in self.allowed_roots:
            r = os.path.realpath(root)
            if rp == r or rp.startswith(r + os.sep):
                return True
        return False
