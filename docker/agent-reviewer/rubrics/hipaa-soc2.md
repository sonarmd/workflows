# Overlay - HIPAA / SOC2

SonarMD handles Protected Health Information. This overlay flags
HIPAA-relevant and SOC2-relevant gaps in the diff.

## What to look at

### PHI handling

- PHI written to logs (patient name, MRN, DOB, SSN, address, diagnosis,
  insurance info).
- PHI in error messages, exception stacks, telemetry events.
- PHI in URL paths or query strings (URLs are logged by proxies, CDNs,
  browsers).
- PHI written to analytics / product-instrumentation events.
- PHI exposed to third-party services without a Business Associate
  Agreement (BAA).

### Audit logging

- Data access (read/write) to PHI records without an audit-log entry.
- Audit-log entries missing the actor, target record, action, and
  timestamp.
- Changes to existing audit-log producers that drop a field or change
  semantics.

### Encryption

- New persistent store (S3 bucket, RDS instance, Mongo collection,
  Lambda env var) without encryption at rest.
- Outbound HTTP without TLS (`http://` instead of `https://`).
- Encryption keys checked into code or stored unencrypted.
- KMS key reuse across environments (prod key used in staging).

### Access control

- New API endpoint without tenant scoping (one user can read another
  tenant's PHI).
- New database query without a tenant filter / row-level security
  predicate.
- IAM role / policy widening that affects PHI-bearing resources.

### Third-party data sharing

- New integration with a third-party service that will receive PHI
  without a BAA.
- LLM call (Anthropic, OpenAI, etc.) with PHI in the prompt or
  context.
- Webhook / outbound to a partner without contractual coverage.

### Rollback safety

- Migration that destroys PHI without backup.
- Hotfix that rewrites historical records without audit-log entries for
  each.
- Feature flag flip that suddenly broadens PHI access scope.

### SOC2 controls

- Changes to authentication (MFA, session, password policy) without a
  corresponding control-evidence update.
- Changes to monitoring / alerting on PHI-bearing systems.
- Changes to backup or disaster recovery procedures.

## Severity calibration for this overlay

- `critical` - confirmed PHI exposure to a non-BAA-covered destination
  (LLM, analytics provider, log shipper) or destruction without backup.
- `high` - likely PHI exposure (PHI in a log that ships off-system,
  missing tenant filter on a query, encryption disabled), or missing
  audit-log entry for a PHI access.
- `medium` - control weakness (over-permissive role, missing alarm on a
  PHI-bearing resource).
- `low` - documentation / evidence gap.

## Output discipline

- Category MUST be `compliance`.
- Overlay field MUST be `hipaa-soc2`.
- Anchor to the line of the offending operation (where the log line is
  emitted, where the PHI flows out, where the encryption setting is
  configured), not where the data originates.
- Cite the specific control concern in the rationale (e.g., "logs ship
  to Datadog, which is NOT BAA-covered for this workload").
