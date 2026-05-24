# Clean Architecture reference card

## The layers (in dependency direction)

```
interface      ← HTTP handlers, CLI parsers, queue consumers
    ↓
application    ← use cases, services that orchestrate domain ops
    ↓
domain         ← entities, value objects, aggregates, domain services
    ↑
infrastructure ← repositories, DB adapters, external API clients
```

Dependencies point INWARD. Domain knows nothing of the layers around it.

## The invariant

- **Inner layers do not import from outer layers.**
- The domain layer never imports `Mongoose.Document`, `Request`, `Response`, a Redis client, an HTTP status code.
- The application layer talks to the domain and to abstract ports (interfaces). Concrete adapters (infrastructure) implement those ports.

## Smells to flag

- Domain type that contains `_id` (Mongo persistence shape) or `created_at` (DB column).
- Service method returning a Mongoose `Document` to a controller.
- A new `import` in a `domain/` file that points at `infrastructure/`.
- An HTTP status code (`404`, `401`) referenced inside the domain.
- A response envelope (`{ data, error, meta }`) shaped by the transport leaking into a domain return value.

## How to verify

The `dependency-direction.sh` analyzer flags these mechanically. Use its output as a starting point — confirm by reading the imports yourself if a finding feels borderline.

## When this card is relevant

Default rubric's **dependency direction** and **abstraction leakage** sections. Most architecture findings cite this card directly or indirectly. Cite the layer of the offending file and the layer of the import; specificity wins reviews.
