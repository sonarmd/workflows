# Overlay - SENIOR EYE

Apply the staff-engineer lens. You are looking for the things a senior
reviewer would actually flag - not nitpicks, not theoretical issues, but
the concrete risks and gaps that matter when this change lands.

## What to look at

### Blast radius

- What does this change touch that the diff doesn't show? Shared utility
  modified - who else calls it? Schema field renamed - what consumers
  break?
- Changes to logging / metrics / instrumentation that could break
  dashboards, alerts, or SOC2 evidence trails.

### Missing tests for changed behavior

- New code path with no test exercising it.
- Bug fix with no regression test pinning it.
- Behavior change to existing code without an updated test.
- Tests that exercise the happy path only when error paths are also new
  or changed.

### Things juniors miss

- Resource leaks (unclosed file handles, untimed-out connections,
  forgotten event listeners).
- Race conditions / TOCTOU.
- Off-by-one on pagination / batching.
- Misuse of async/await (forgotten `await`, parallel-when-should-be-serial).
- Error swallowing (`catch {}`, errors logged but not propagated).
- Mutation of caller's input objects.

### Reversibility

- Schema migration that's hard to undo.
- Config change that requires coordinated re-deploy to revert.
- Feature flag that's referenced from production paths but cannot be
  flipped off without code change.

### Observability gaps

- New error path with no logging.
- New external call with no metric / timeout / retry policy.
- Log lines that could leak PHI / secrets.

## Severity calibration for this overlay

- `high` - concrete risk on landing (missing tests for behavior changes
  with risk, blast-radius surprise, observability gap on a critical
  path).
- `medium` - significant gap worth fixing before merge.
- `low` - nit a senior would mention but not block on.

## Output discipline

- Category for overlay findings:
  - Missing tests / observability / reversibility -> `maintainability`.
  - Coupling / blast radius -> `coupling`.
- Overlay field MUST be `senior-eye`.
- Be specific. "Add a test" is not actionable; "missing regression test
  for the empty-array branch on line 42" is.
