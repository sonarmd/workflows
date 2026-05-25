# API design reference card

For HTTP, GraphQL, RPC, and event-payload changes.

## Naming

- Verbs are HTTP methods (GET/POST/PUT/PATCH/DELETE) — not in the URL. `POST /users` not `POST /users/create`.
- Nouns are resources, plural. `/users/123` not `/user/123`.
- Filters and pagination as query params: `?status=active&page=2`.
- GraphQL fields named for what they return, not how they're computed.

## Versioning

- Breaking changes require a version bump OR a backward-compatible migration period.
- New optional fields are non-breaking (additive). Removing or renaming a field is breaking.
- Old clients must continue to work until the new contract is broadly adopted.

## Error model

- Errors return a consistent shape: `{ code, message, details }` or a similar structure used across the whole API.
- HTTP status codes match semantic meaning: 400 (client error), 401 (auth), 403 (authz), 404 (not found), 409 (conflict), 422 (validation), 500 (server).
- Error messages are safe to show users (no stack traces, no internal IDs, no PHI).

## Pagination

- Cursor-based (`?cursor=abc`) preferred over offset (`?page=2`) for large or shifting datasets.
- Response includes `next_cursor` or `has_more` — never make the client compute it.

## Idempotency

- Mutations that may be retried (charges, sends, side-effecting calls) accept an `Idempotency-Key` header.
- Server tracks recent keys and returns the same response on retry.

## Smells to flag

- New endpoint with no auth check (and no documented "intentionally public" rationale).
- Different error shapes across endpoints in the same API.
- Removing a field without deprecation period.
- Inconsistent naming (one endpoint uses camelCase response, another uses snake_case).
- New GraphQL field that fans out to N+1 database queries.
- Webhook payloads with no version field — future evolution is blocked.
- HTTP 500 returning client-actionable errors (should be 4xx).
- Mutations that aren't idempotent and don't accept an idempotency key.

## When this card is relevant

Any diff that adds or modifies an endpoint, a GraphQL schema, an event/webhook payload, or an exported function used as an API surface. Flag inconsistencies with the rest of the API surface — pattern-fit analyzer can show you what neighbors look like.
