# Test coverage reference card

## What to require

- **Behavior changes need behavior tests.** New if-branch, new error path, new public function -> there must be a test exercising it.
- **Bug fixes need regression tests.** A fix without a test pinning the bug is one revert away from coming back.
- **Public API changes need contract tests.** New endpoint, new exported function, new event payload -> at least one test exercising the new shape.

## What NOT to require

- 100% line coverage. Coverage is a signal, not a goal. A 100%-covered codebase with shallow tests is worse than 80% with deep tests.
- Tests for trivial getters/setters, pure-passthrough wrappers, generated code.
- Tests for code clearly marked as deprecated and slated for removal.

## Smells to flag

- New function with branching logic, no test exercising both branches.
- Modified function whose existing test wasn't updated to match the new behavior.
- A test added that only exercises the happy path of new code where error paths are also new.
- A test that mocks everything (no real assertion of behavior - just "the function ran").
- Snapshot tests for non-deterministic output (timestamps, UUIDs leaking into snapshots).

## How to surface

The `test-coverage.sh` analyzer flags changed source files that have no corresponding test file change. Use its output as a starting point - confirm by looking at the diff whether the change actually needed a test (architectural refactor with no behavior change may legitimately have no test changes).

## When this card is relevant

Senior-eye overlay's **missing tests for changed behavior** check. Use whenever a finding might be "this change adds risk without adding test coverage." Pair with concrete diff lines, not just file names.
