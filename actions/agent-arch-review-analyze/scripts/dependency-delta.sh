#!/usr/bin/env bash
#
# dependency-delta.sh - detect additions to package manifests in a PR
# diff. Useful for grounding the dependency-judge lens: every new dep
# is a long-term commitment that deserves explicit consideration.
#
# Usage:  dependency-delta.sh <diff.patch>
# Output: tab-separated lines:
#           <manifest-file>  <ecosystem>  <added-dep>  <version-or-empty>
#         or, if none:
#           OK  no dependency additions detected
#
# Supports: package.json, requirements.txt, pyproject.toml (PEP 621),
# Cargo.toml, go.mod, Gemfile.

set -euo pipefail

DIFF="${1:?usage: dependency-delta.sh <diff.patch>}"

if [[ ! -f "$DIFF" ]]; then
  echo "diff file not found: $DIFF" >&2
  exit 1
fi

FOUND=0

# Walk file blocks; for each manifest file, scan the `+` lines for new deps.
# We use awk to split the diff into per-file blocks then a per-format
# parser to extract additions.

CURRENT_FILE=""
CURRENT_FORMAT=""

while IFS= read -r line; do
  case "$line" in
    "diff --git "*)
      # Extract the b-side path
      CURRENT_FILE=$(echo "$line" | awk '{print $4}' | sed 's|^b/||')
      case "$CURRENT_FILE" in
        */package.json|package.json)         CURRENT_FORMAT="package-json" ;;
        */requirements*.txt|requirements*.txt) CURRENT_FORMAT="requirements-txt" ;;
        */pyproject.toml|pyproject.toml)     CURRENT_FORMAT="pyproject-toml" ;;
        */Cargo.toml|Cargo.toml)             CURRENT_FORMAT="cargo-toml" ;;
        */go.mod|go.mod)                     CURRENT_FORMAT="go-mod" ;;
        */Gemfile|Gemfile)                   CURRENT_FORMAT="gemfile" ;;
        *)                                   CURRENT_FORMAT="" ;;
      esac
      continue
      ;;
  esac

  [[ -z "$CURRENT_FORMAT" ]] && continue

  # Only consider added lines (single + prefix; skip +++  headers).
  case "$line" in
    "+++"*) continue ;;
    "+"*) ;;
    *) continue ;;
  esac
  ADDED="${line#+}"

  case "$CURRENT_FORMAT" in
    package-json)
      # Match "name": "version" lines inside a dependency block.
      # Heuristic: any line of the form "name": "constraint" with a
      # name that looks like an npm package. Filter common false
      # positives (scripts, config values).
      if [[ "$ADDED" =~ \"([@a-zA-Z0-9_./-]+)\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        NAME="${BASH_REMATCH[1]}"
        VER="${BASH_REMATCH[2]}"
        # Skip scripts (values look like commands), engines, license, name, version, etc.
        case "$NAME" in
          name|version|description|main|module|types|license|author|repository|bugs|homepage|engines|scripts|workspaces|private|publishConfig) continue ;;
        esac
        # Skip values that look like shell commands (contain space + word + dash flag, or are very long)
        case "$VER" in
          *' '*' '*) continue ;;
        esac
        if [[ ${#VER} -gt 80 ]]; then continue; fi
        printf '%s\tnpm\t%s\t%s\n' "$CURRENT_FILE" "$NAME" "$VER"
        FOUND=$((FOUND+1))
      fi
      ;;
    requirements-txt)
      # Format: pkg==1.2.3, pkg>=1.0, pkg
      if [[ "$ADDED" =~ ^[[:space:]]*([A-Za-z0-9_.-]+)([[:space:]]*[<>=!~][^[:space:]#]*)?[[:space:]]*(\#.*)?$ ]]; then
        NAME="${BASH_REMATCH[1]}"
        VER="${BASH_REMATCH[2]}"
        VER="${VER// /}"
        # Skip pip directives and -r includes
        case "$NAME" in
          ""|-r|--*) continue ;;
        esac
        printf '%s\tpypi\t%s\t%s\n' "$CURRENT_FILE" "$NAME" "${VER:-}"
        FOUND=$((FOUND+1))
      fi
      ;;
    pyproject-toml)
      # PEP 621: dependencies = ["pkg>=1.0", ...]
      # We catch the per-item additions; full multi-line dependency arrays
      # may be split across many + lines.
      if [[ "$ADDED" =~ \"([A-Za-z0-9_.-]+)([[:space:]]*[<>=!~][^\"]*)?\" ]]; then
        NAME="${BASH_REMATCH[1]}"
        VER="${BASH_REMATCH[2]}"
        printf '%s\tpypi\t%s\t%s\n' "$CURRENT_FILE" "$NAME" "${VER// /}"
        FOUND=$((FOUND+1))
      fi
      ;;
    cargo-toml)
      # [dependencies] table entries: name = "1.0"  or  name = { version = "1.0" }
      if [[ "$ADDED" =~ ^[[:space:]]*([A-Za-z0-9_-]+)[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
        printf '%s\tcrates\t%s\t%s\n' "$CURRENT_FILE" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        FOUND=$((FOUND+1))
      elif [[ "$ADDED" =~ ^[[:space:]]*([A-Za-z0-9_-]+)[[:space:]]*=[[:space:]]*\{ ]]; then
        printf '%s\tcrates\t%s\t(table)\n' "$CURRENT_FILE" "${BASH_REMATCH[1]}"
        FOUND=$((FOUND+1))
      fi
      ;;
    go-mod)
      # require ( ... ) blocks add lines like:  module/path v1.2.3
      if [[ "$ADDED" =~ ^[[:space:]]+([a-zA-Z0-9._/-]+)[[:space:]]+(v[0-9][^[:space:]]*) ]]; then
        printf '%s\tgo\t%s\t%s\n' "$CURRENT_FILE" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        FOUND=$((FOUND+1))
      fi
      ;;
    gemfile)
      # Ruby Gemfile: gem 'name', '~> 1.0'
      if [[ "$ADDED" =~ gem[[:space:]]+[\'\"]([A-Za-z0-9_-]+)[\'\"](,[[:space:]]*[\'\"]([^\'\"]+)[\'\"])?(,|[[:space:]]|$) ]]; then
        printf '%s\trubygems\t%s\t%s\n' "$CURRENT_FILE" "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]:-}"
        FOUND=$((FOUND+1))
      fi
      ;;
  esac
done < "$DIFF"

if [[ "$FOUND" -eq 0 ]]; then
  echo "OK	no dependency additions detected"
fi
