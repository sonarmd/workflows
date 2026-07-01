---
title: CI SOC2 security-evidence + Jira development-panel surfacing
date: 2026-07-01
status: planning
blast_radius: high   # shared sonarmd/workflows ci-core; fans out to every caller repo
session: 3f204256
---

# Goal

Make every change across every repo produce standardized, auditable evidence that
the org runs the security + testing controls a SOC 2 auditor expects, and surface
that evidence against the Jira work item.

Driver: passing SOC 2 (and adjacent) audits. NOT cosmetic. Evidence must be honest -
no fabricated coverage, no claiming a control runs when it does not.

# What already exists in ci-core.yml (baseline)

- Test steps (caller-provided: `yarn lint`, `yarn test:shard`, `yarn build`).
- `test_report_path` input (junit.xml) - threaded to bundle-release only.
- Security scan action: semgrep (SAST) + gitleaks (secret) + trivy (SCA/secret/misconfig). Report-only, logs to stdout, NO file output, NO artifact.
- Quality scan action: jscpd (duplication) + knip (dead code). Report-only, stdout only.
- sbom-generator action exists (supply-chain evidence) - not currently wired into ci-core.
- sign-release + build attestations (artifact integrity) - wired.

Gap: nothing writes scan/test results to files, uploads them, consolidates them,
labels them with control nomenclature, or pushes anything to Jira.

# Standard control nomenclature (map tool -> control)

| Evidence file            | Tool           | Standard control name                         | SOC2 TSC ref |
|--------------------------|----------------|-----------------------------------------------|--------------|
| sast.semgrep.json        | Semgrep        | Static Application Security Testing (SAST)     | CC7.1        |
| sca.trivy.json           | Trivy (vuln)   | Software Composition Analysis (SCA)            | CC7.1        |
| secrets.gitleaks.json    | Gitleaks       | Secret Scanning                               | CC6.1 / CC6.8|
| secrets.trivy.json       | Trivy (secret) | Secret Scanning (corroborating)               | CC6.1        |
| iac.trivy.json           | Trivy (misconfig) | IaC / Misconfiguration Scanning            | CC7.1        |
| tests.junit.xml          | test runner    | Automated Testing (unit/integration)          | CC8.1        |
| duplication.jscpd.json   | jscpd          | Code Quality - duplication                    | CC8.1        |
| deadcode.knip.json       | knip           | Code Quality - unused code/deps               | CC8.1        |
| sbom.spdx.json           | sbom-generator | Software Bill of Materials                    | CC7.1 / CC8.1|
| attestation.intoto.jsonl | GH attestation | Build Provenance / artifact integrity         | CC8.1        |

# Deliverables

## A. Scan actions emit machine-readable output files
Edit `actions/security-scan` and `actions/quality-scan` to ALSO write structured
output (json/sarif) to a caller-specified `output_dir`, in addition to current
stdout logging. Keep report-only semantics (no gating - per workflows-is-dumb rule).

## B. New composite action `ci-evidence-bundle`
One thing: collect every evidence file produced this run into `ci-evidence/`,
write `INDEX.md` (human, labels each file with its control name + TSC ref from the
table above) and `manifest.json` (machine: {control, tool, file, sha256, status,
counts}). Upload as artifact `ci-evidence-<treehash>` (retention 90d). This is THE
single labeled artifact the user asked for.

## C. Surface to Jira - DECISION REQUIRED (see below)
The GitHub-for-Jira app auto-links commits/branches/PRs ONLY. It syncs build/deploy
*status* but never test counts (does not parse JUnit). Two approaches:

- **C1 (evidence-link, low cred):** keep using existing agora Jira OAuth. On CI
  completion, add a Jira remote issue link to the Actions run + the evidence artifact,
  and (optionally) a concise comment: "Security controls: SAST pass, SCA pass, Secret
  scan pass, Tests 142/142." Issue keys parsed from branch/commit/PR. No new credential.
  Auditor clicks through to the evidence bundle. Honest, cheap, robust.

- **C2 (full dev-info push):** stand up a dedicated Atlassian OAuth2 (3LO) or Connect
  app with dev-info WRITE scope; store secret in agora_vault; CI POSTs builds (with
  testInfo total/passed/failed/skipped) + deployments to the dev-info API. Richest
  panel (build + test counts render natively). New credential + must reconcile with the
  GitHub-for-Jira app to avoid duplicate build entries.

Recommendation: C1 first (unblocks audit evidence now, no new attack surface), then
C2 as a follow-up if the native test-count panel is specifically required.

# Rules / constraints
- Rule 0: base off latest main. Repo is on `fix/bundle-eas-no-local-dist` now - must
  stash/verify no dangling work, checkout main, fetch, pull, cut a fresh branch.
- cicd.md: ci-core stays report-only; new logic goes in composite actions, one-thing each.
- Do NOT touch `staging`. Default PR base for this repo: confirm before opening PR.
- Evidence honesty: a control that did not run must NOT appear as passed. Missing =
  explicitly "not-run" in manifest, never silently omitted.

# Open decisions (need user)
1. C1 vs C2 (evidence-link vs full dev-info push).
2. Confirm control nomenclature table matches what the auditor expects.
3. Screenshots of desired panel layout (blocked: Desktop TCC denied this session).

# Status
Planning only. No code changed. Auth path (C1/C2) is the gating decision.
