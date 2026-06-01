# CI/CD Architecture

## Overview

SonarMD CI/CD uses a **contract-based gate** model. Central workflows define quality contracts - they validate results with independently verified evidence but never execute project commands. Each repository owns its own CI implementation and calls the gates at stage boundaries.

```
Repo (owns implementation)          Central (owns contracts)
--------------------------          ------------------------
lint, typecheck                 --> static-analysis-gate
test + JUnit XML artifact       --> test-gate (downloads + parses XML)
build                           --> build-gate
                                    deploy-gate (requires all 3)
```

## Repository Map

| Repository | Purpose | CI | Deploy | Gate Integration |
|-----------|---------|-----|--------|-----------------|
| `sonarmd/workflows` | Central gates, actions, utilities | - | - | Defines the contracts |
| `sonarmd/frontend` | React monorepo (4 apps + shared) | Path-filtered per-app testing | S3 sync per app | Per-app JUnit XML artifacts |
| `sonarmd/triggr_api` | Express.js API | 4-shard parallel + MongoDB | OIDC + ECS | Mocha JSON -> JUnit XML per shard |
| `sonarmd/frontend-patient-app` | React Native mobile | Jest + jest-junit | EAS Build (tag-triggered) | Single JUnit XML artifact |

## Gate Flow

### CI (every push + PR)

```
+-------------+    +----------------------+    +-------------+
|   lint       |--->| static-analysis-gate |    |             |
|   typecheck  |--->| (lint_file_count>0)  |    |   merge     |
+-------------+    +----------------------+    |   blocked   |
                                                |   until     |
+-------------+    +----------------------+    |   both      |
|   test       |--->|    test-gate         |    |   gates     |
| + JUnit XML  |--->| (downloads XML,      |--->|   pass      |
|   artifact   |    |  counts <testcase>)  |    |             |
+-------------+    +----------------------+    +-------------+
```

### Deploy (tag-triggered)

```
+-------------+    +----------------------+    +----------------------+    +----------+
|   build      |--->|    build-gate        |--->|    deploy-gate       |--->|  deploy   |
|   (per repo) |    | (status check)       |    | (SA + test + build)  |    |  (S3/ECS) |
+-------------+    +----------------------+    +----------------------+    +----------+
```

CI gates (`static-analysis-gate`, `test-gate`) already passed on the commit. Deploy workflows pass `success` for those and validate the build gate from the deploy build.

## Evidence Chain

The test gate's evidence chain is bound to the commit SHA:

1. GitHub Actions triggers a workflow run at `github.sha`
2. The test job runs at that SHA and produces a JUnit XML report
3. `upload-artifact` ties the report to that workflow run
4. The test gate (in the same run) downloads the artifact
5. The gate parses `<testcase>` elements independently
6. `github.sha` appears in the gate's log output for auditability

No one can fake this because:
- Artifacts are scoped to the workflow run (can't inject from another run)
- CODEOWNERS protects the workflow files (can't remove gate calls)
- Branch protection requires the gate checks (can't merge without them)
- The gate does its own parsing (doesn't trust caller-provided counts)

## Deployment Patterns

### Frontend (S3 + CloudFront)

```
Tag push (dev-fe-*, stg-fe-*, prd-fe-*)
  -> Resolve environment from tag prefix
  -> Build all 4 apps in parallel
  -> build-gate (aggregated build result)
  -> deploy-gate (SA=success, test=success, build=gate result)
  -> S3 sync per app + CloudFront invalidation
  -> Slack notification + metrics
```

### API (OIDC + ECS)

```
Tag push (dev-api-*, stg-api-*, prd-api-*)
  -> Resolve environment from tag prefix
  -> Build + package artifact
  -> Upload to S3 via OIDC
  -> build-gate
  -> deploy-gate
  -> Generate configuration.json from 1Password
  -> SSM-based deployment to EC2/ECS
  -> Slack notification + metrics
```

### Mobile (EAS Build)

```
Tag push (stg-mobile-*, prd-mobile-*)
  -> Resolve environment from tag prefix
  -> deploy-gate (SA=success, test=success, build=skipped)
  -> EAS Build (preview or production + auto-submit)
  -> Slack notification
```

## Secrets

| Secret | Purpose |
|--------|---------|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | S3 deploy for frontend |
| `AWS_DEPLOY_ROLE_ARN` | OIDC role for API deployment |
| `OP_SERVICE_ACCOUNT_TOKEN` | 1Password service account for config generation |
| `SLACK_WEBHOOK_URL` | Slack deploy notifications |
| `EXPO_TOKEN` | EAS CLI authentication for mobile |

## Composite Actions

| Action | Purpose |
|--------|---------|
| `setup-node` | Detects Node version (Volta or input), installs with yarn cache |
| `detect-changed-apps` | Path filtering for frontend monorepo (admin, patient, provider, seat, shared) |
