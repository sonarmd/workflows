# Abstraction discipline reference card

The right time to abstract is when you have two real callers, not one and a wish.

## The two-of-something rule

Before introducing an interface, base class, strategy, factory, or generic:

- Are there at least TWO concrete things this abstraction will serve, BOTH living in the diff or already in the codebase?
- If there's one real caller and one hypothetical future caller, the abstraction is premature.

## YAGNI filter

If the answer to any of these is "no", you don't need the abstraction yet:

- Is the second concrete implementation in the same change OR already in the repo?
- Does the abstraction reduce more code than it adds?
- Does the abstraction make the code easier to understand, not harder?

## Smells to flag

- **Factory of one** - `class UserFactory { create(...) { return new User(...) } }` for a type with one creation path.
- **Strategy of one** - a strategy interface with a single implementation, where the call site has no plausible second strategy.
- **Base class with one subclass** - solve via composition, function, or just inlining.
- **Generic with one instantiation** - `Container<T>` used only as `Container<User>`. The type parameter is dead.
- **Configuration that's never configured** - a new env var, feature flag, or constructor parameter that only ever holds one value.

## Cost of indirection

Every abstraction costs:

- A name (which must be good)
- A place to look (jumping to definitions during reading)
- A new file or new module boundary
- A reader's attention budget for "why is this here"

The abstraction has to pay for those costs in real maintainability gains.

## When this card is relevant

Default rubric's **fit with existing patterns** section. Use this card when you see new interfaces, base classes, factories, strategies, or generics introduced in the diff. Apply the two-of-something rule mechanically - if you cannot name the second concrete user living in the codebase right now, the abstraction is probably premature.
