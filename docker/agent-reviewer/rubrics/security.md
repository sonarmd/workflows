# Overlay — SECURITY

Apply the security review lens. You are looking for exploitable bugs and
policy violations, not theoretical hardening.

## What to look at

### Injection

- SQL: string concatenation into queries, missing parameterization.
- Command: `exec`, `spawn`, `system` with user input.
- NoSQL: operator injection (Mongo `$where`, `$expr` with user input).
- LDAP / XPath / template injection.

### Authentication & authorization

- New endpoint with no auth check.
- New endpoint with auth but no authorization (any logged-in user can
  access any tenant's data).
- Auth bypass via parameter tampering, mass-assignment, IDOR.
- Session/token handling: secure flag, httpOnly, sameSite, expiry.

### Secret handling

- Secrets in code, environment files committed, hardcoded API keys.
- Secrets in logs, error messages, stack traces.
- Secrets passed through query strings.
- Credentials stored without encryption at rest.

### Data exposure

- Object returned with more fields than the caller should see (over-fetch
  + over-return).
- PHI / PII in logs, telemetry, or analytics events.
- CORS / CSP / referrer-policy weakened without justification.
- File upload endpoints with no content-type / size / extension check.

### SSRF / XSS

- Outbound HTTP to user-controlled URLs without allowlist.
- User content rendered without escaping (innerHTML, dangerouslySetInnerHTML
  in React, raw template interpolation).

### Cryptography

- Weak algorithms (MD5/SHA1 for security, ECB mode, fixed IVs).
- Hand-rolled crypto.
- Insecure randomness for security purposes (`Math.random()` for tokens).

### Permissions / IAM

- Cloud resource policies wider than needed (S3 bucket public, IAM with
  `*` action).
- Database user with more privileges than the workload requires.
- File permissions too permissive (`chmod 777`, `0o666`).

## Severity calibration for this overlay

- `critical` — active exploit possible from any caller (anonymous IDOR,
  command injection on a public endpoint, hardcoded prod secret in source).
- `high` — exploit possible with some constraint (authenticated IDOR,
  XSS on internal page, secret in log that ships off-system).
- `medium` — security weakness without an obvious exploit path
  (weak crypto, missing rate limit, over-permissive CORS).
- `low` — defense-in-depth gap (missing security header).

## Output discipline

- Category MUST be `security`.
- Overlay field MUST be `security`.
- Confidence: only emit `critical` or `high` when you can articulate the
  attacker, the entry point, and the outcome. Otherwise drop to `medium`
  with `low` confidence.
- Anchor to the line where the vulnerable operation occurs, not where the
  data originates.
