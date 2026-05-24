# Failure mode reference card

When a new code path can fail, the question is: what does the system do when it does?

## The categories

1. **External dependency failure** — DB unreachable, API timeout, broker down. Almost always temporary; almost always probable.
2. **Internal fault** — null deref, divide-by-zero, off-by-one. Should be caught in tests but slip through.
3. **Data integrity** — corrupt payload, stale cache, unique constraint violation, partial write.
4. **Operational** — disk full, OOM, network partition, daemon crash.

## The patterns

- **Timeout** — every outbound call has a deadline. Never wait indefinitely.
- **Retry with backoff and jitter** — for idempotent operations with transient failure modes. Cap retry count.
- **Circuit breaker** — when an external dep is down, stop hammering it. Open the breaker, fail fast.
- **Bulkhead** — isolate failure domains. One subsystem failing shouldn't take down the others.
- **Idempotency** — see api-design-card. Retries must be safe.
- **Graceful degradation** — when a non-critical dep is down, serve a degraded experience, not a 500.
- **Dead-letter queue** — for async work that can't be processed after N tries, park it for human review rather than dropping or looping.

## Smells to flag

- New outbound HTTP call with no timeout.
- New external call with no retry policy AND no graceful-degrade path.
- `catch {}` (or equivalent) — swallowing exceptions silently.
- Errors logged but not propagated to the caller — invisible failures.
- New worker with no DLQ (failed messages just retry forever).
- `if err != nil { return nil }` patterns that hide a real failure.
- Caching that doesn't invalidate on the write path — stale-data risk.
- New synchronous call from a request handler into a flaky downstream — should be async / queued.

## When this card is relevant

Any diff that adds an outbound call, a new exception class, a try/catch block, a worker, a queue producer/consumer, a cache. Be specific about WHICH failure the new code is exposed to and what the system does when it fires.
