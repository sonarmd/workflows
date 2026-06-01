# DDD reference card

One page. Refer to this when judging domain modeling.

## The ubiquitous language

- Code and conversation use the same terms for the same things.
- A new synonym for an existing domain concept is a smell. Flag it.
- Names describe what something IS in the domain, not how it's used in code (`approvedClaim`, not `claimsList`).

## Entities vs value objects

- **Entity** - identity matters. `User { id, name, ... }`. Two users with the same name are different.
- **Value object** - defined by its values. `Money { amount, currency }`. Two `Money(5, USD)` are interchangeable. Immutable.
- Flag: domain concepts modeled as raw primitives (`amount: number` instead of `Money`) - primitive obsession.

## Aggregates

- An aggregate is a cluster of objects treated as one unit for consistency.
- Has a single root entity. External code only references the root.
- All invariants of the aggregate hold at every transaction boundary.
- Flag: external code reaching past the root into internal members.

## Bounded contexts

- Different parts of a large system can use the same word for different things, as long as boundaries are explicit.
- A `User` in billing is not the same as a `User` in clinical records.
- Flag: a single shared type across contexts that means subtly different things.

## When this card is relevant

The default rubric's **naming** and **domain boundary** sections lean on these definitions. If the diff introduces a new domain type, ask: is it an entity or value object? Does it belong inside an aggregate? Does its naming match the ubiquitous language already established in the repo?
