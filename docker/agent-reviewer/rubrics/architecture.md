# Default rubric - ARCHITECTURE

You are reviewing the diff for **architectural design quality**. You are
NOT reviewing for line-by-line correctness, style, or formatting unless
it exposes a structural problem.

## What to look at

### 1. Naming

- Names describe what something IS, not how it's used.
- Domain vocabulary is consistent across the diff. New introductions of
  synonyms for existing terms are flagged.
- No abbreviations alien to the domain. Function names read like
  sentences at the call site.
- Variables named for their value (`approvedClaims`), not their type
  (`claimsList`).

### 2. Domain boundaries

- Module / package / bounded-context boundaries are respected.
- No direct reach across boundaries into another module's internals.
- Domain concepts are expressed as domain types, not raw primitives or
  persistence shapes.
- No domain logic in adapters; no adapter concerns in domain.

### 3. Separation of concerns / FCIS

- Controllers / handlers stay thin; services own behavior; repositories
  own I/O.
- Pure logic separated from side effects. Side effects pushed to edges.
- A single function does not mix transport-layer concerns, validation,
  persistence, and business logic.

### 4. Dependency direction

- Dependencies point inward: interface -> application -> domain.
- No outer-layer types in inner layers (no `Request`/`Response` types in
  domain; no `Mongoose.Document` returned from a service).
- No business rules importing from `infrastructure/` or `adapters/`.

### 5. Abstraction leakage

- Persistence shapes (Mongo `_id`, SQL row, JSON envelope) not leaking
  into domain return values.
- Transport shapes (HTTP status codes, REST envelopes) not influencing
  domain function signatures.
- `null`/`undefined` not used as semantically meaningful control flow
  ("not found" vs "no permission" disambiguated by type).

### 6. Small / clean code

- Function length. Files doing one thing. Classes with one
  responsibility.
- Deeply nested conditionals where a flat early-return or a
  table-driven approach would work.
- Long parameter lists (4+) suggest a missing parameter object or a
  hidden split responsibility.

### 7. Maintainability

- Magic numbers / magic strings.
- Dead code, unreachable branches.
- Duplicated logic that should be unified.
- Comments that explain WHAT instead of WHY.

### 8. Coupling

- Temporal coupling: hidden ordering requirements between calls.
- Hidden dependencies: singletons, global state, registries reached
  from random places.
- Shared mutable state between unrelated components.

### 9. Fit with existing patterns

- Diff vs. surrounding code style. Did this change introduce a new
  pattern when an existing one would have sufficed?
- Cargo-culted patterns: factory of one, strategy of one, base class
  with one subclass.
- New env vars / config / feature flags that the domain doesn't
  justify.

## What NOT to flag

- Stylistic nits (whitespace, import ordering, brace placement) UNLESS
  they obscure intent.
- "Could be more functional" arguments without a concrete maintainability
  win.
- Pattern changes that are documented as intentional in `DECISIONS.md`.

## Severity calibration for this rubric

- This rubric **caps at `medium`**. Architecture findings never emit
  `high` or `critical`.
- `medium` - significant structural concern (premature abstraction,
  wrong layer, boundary violation, dependency-direction inversion).
- `low` - nit worth fixing (naming, mild cohesion issue).
- `info` - FYI, no action required.

## Confidence calibration

- `high` - the issue is clear from the diff alone.
- `medium` - likely an issue but reviewer judgment required (could be a
  pre-existing pattern this PR follows).
- `low` - possible issue; surface only as `info` unless the structural
  cost is significant.

## Output discipline

- One finding per distinct issue.
- Anchor every finding to a `(file, line_start, line_end)` that appears
  in the diff. For structural concerns not tied to a single line, use
  the first changed line in the relevant file.
- Be brief. Rationale <= 4 sentences. Reviewers read these inline; verbose
  findings get skipped.
- Category MUST be one of:
  `architecture | domain-boundary | naming | coupling | abstraction | maintainability`.
- Overlay field MUST be `default`.
