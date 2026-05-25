# Functional Core / Imperative Shell reference card

## The principle

- **Core** — pure functions. Same input → same output. No I/O. No mutable shared state. Easy to test (no mocks).
- **Shell** — imperative orchestration. Calls the core. Performs I/O. Threads side effects.

Pure logic and I/O get separated; you can test the core exhaustively without touching the database, the network, or the clock.

## Smells to flag

- A function that takes raw arguments AND opens a database connection AND returns a domain decision.
- A "service" that mixes computation with persistence in a single method.
- Tests that have to mock the database to verify business logic — usually means the logic is trapped inside the shell.
- Pure functions parameterized on `Date.now()` or `Math.random()` directly — should take the value as a parameter (the shell supplies it).

## What good looks like

```
// shell — talks to outside
async function approveClaim(claimId) {
  const claim = await claimsRepo.find(claimId);   // I/O
  const decision = decideApproval(claim);         // pure core
  await claimsRepo.save(decision.appliedTo);      // I/O
  notify(decision);                                // I/O
}

// core — pure
function decideApproval(claim) {
  if (!claim.meetsMinimumThreshold()) return reject(claim, "below threshold");
  if (claim.hasOpenDisputes())       return reject(claim, "open dispute");
  return approve(claim);
}
```

## When this card is relevant

Default rubric's **separation of concerns** section. The split between core and shell is one of the cleanest tests for whether concerns are separated. If you can't extract a pure function from a method without ten paragraphs of refactoring, the method is doing too much.
