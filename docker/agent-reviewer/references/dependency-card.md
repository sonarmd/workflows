# Dependency review reference card

A new dependency is a long-term commitment. Treat it as such.

## What to ask before any new dep

1. **Could this be done with the stdlib?** Many dependencies wrap 5 lines of stdlib for a worse API.
2. **Do we already have a dep that does this?** Adding lodash for a 3-line debounce when we already have underscore is a smell.
3. **Is the maintenance health solid?** Last commit < 12 months. Open issues responded to. Not a one-person hobby project unless explicitly OK.
4. **What's the transitive surface?** A package with 80 transitive deps adds 80 things to keep updated.
5. **License compatibility?** GPL/AGPL incompatible with proprietary; Apache/MIT/BSD usually fine.
6. **Known CVEs?** Check the advisory database before adopting.
7. **BAA coverage (healthcare)?** If the dep is a third-party service (Sentry, Datadog, an LLM API), does the vendor have a BAA? PHI flowing to a non-BAA service is a compliance violation.

## Smells to flag

- Adding a dep for a 5-line problem.
- Adding a heavyweight dep (e.g. lodash entire) for a single function.
- Adding a dep that's a fork of a more-maintained upstream (forks rot).
- Adding a dep with a known vulnerability advisory still open.
- Adding a dep used only in dev but listed under prod dependencies (or vice versa).
- Adding a transitively-pulled dep at the top level when it's already available transitively (just bloats the lock file).
- Adding a dep with native bindings (gyp, cmake) without considering cross-platform impact.

## How to surface

The `dependency-delta.sh` analyzer detects additions to `package.json`, `requirements.txt`, `Cargo.toml`, `go.mod`, `Gemfile`, `pyproject.toml`. Each addition is worth checking against the questions above.

## When this card is relevant

Whenever the diff touches a package manifest. Adding a dep deserves its own finding — don't bury it in a list of other observations. Cite the specific dep name and what alternatives were considered (or not).
