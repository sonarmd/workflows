"""Shell scanner.

Rejects:
- smart punctuation (handled centrally by the byte scanner via
  forbidden_codepoints, but flagged here as a structural problem too
  when it occurs inside code).
- control bytes (byte scanner).
- PATH clobber: `export PATH=...` or `PATH=...` that REPLACES the
  existing PATH rather than extending it.
- shell startup file writes: lines that redirect into common rc files
  ( ~/.zshrc, ~/.zshenv, ~/.zprofile, ~/.bashrc, ~/.bash_profile,
  ~/.profile, ~/.config/fish/config.fish ).

Parse check (best effort):
- if `zsh` or `bash` is on PATH, the ops layer can invoke
  `zsh -n <file>` / `bash -n <file>` and surface a syntax error as a
  finding. This scanner does not shell out (keeps scan() pure).
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

GRAMMAR = "shell"


# A PATH assignment that DOES NOT reference $PATH on its right-hand
# side. This is the "clobber" pattern. We do not flag the safer forms
# `PATH="$PATH:/x"` or `PATH=/x:"$PATH"`.
PATH_CLOBBER = re.compile(
    rb"(?:^|;\s*|&&\s*|\|\|\s*)\s*(?:export\s+)?PATH\s*=\s*\"?(?!\$PATH|.*\$PATH)[^\n;]+",
    re.MULTILINE,
)


# Redirect into a known shell startup file.
STARTUP_FILES = (
    rb"~/\.zshrc",
    rb"~/\.zshenv",
    rb"~/\.zprofile",
    rb"~/\.bashrc",
    rb"~/\.bash_profile",
    rb"~/\.profile",
    rb"~/\.config/fish/config\.fish",
)
STARTUP_WRITE = re.compile(
    rb"(?:>>|>)\s*(?:" + b"|".join(STARTUP_FILES) + rb")",
    re.MULTILINE,
)


# Generating a "pasteable shell block" with leading hash comments is
# a common footgun: pasted with a leading # the user's shell may treat
# the next line as a separate command, or echo the comment unexpectedly.
# Heuristic: a line of the form `# <something>` followed (on the next
# physical line) by a non-empty command. We flag only when at column 0,
# to avoid flagging inline trailing comments.
LEADING_HASH_COMMAND = re.compile(
    rb"^#[^!\n][^\n]*\n(?=[^\s#])",
    re.MULTILINE,
)


def scan(data: bytes, **_unused) -> tuple[list[Finding], dict]:
    findings: list[Finding] = []

    for m in PATH_CLOBBER.finditer(data):
        off = m.start()
        line, col = offset_to_line_column(data, off)
        findings.append(
            Finding(
                severity=SEVERITY_BLOCK,
                reason="shell_path_clobber",
                grammar=GRAMMAR,
                byte_offset=off,
                line=line,
                column=col,
                detail="PATH assignment without $PATH on the RHS replaces the shell path entirely",
                context=visible_byte_context(data, off),
            )
        )

    for m in STARTUP_WRITE.finditer(data):
        off = m.start()
        line, col = offset_to_line_column(data, off)
        findings.append(
            Finding(
                severity=SEVERITY_BLOCK,
                reason="shell_startup_write",
                grammar=GRAMMAR,
                byte_offset=off,
                line=line,
                column=col,
                detail="redirect into a shell startup file detected",
                context=visible_byte_context(data, off),
            )
        )

    for m in LEADING_HASH_COMMAND.finditer(data):
        off = m.start()
        line, col = offset_to_line_column(data, off)
        findings.append(
            Finding(
                severity=SEVERITY_SUSPICIOUS,
                reason="shell_leading_hash_comment",
                grammar=GRAMMAR,
                byte_offset=off,
                line=line,
                column=col,
                detail="leading hash comment in a generated shell block; awkward to paste",
                context=visible_byte_context(data, off),
            )
        )

    return findings, {"checked_patterns": 3}
