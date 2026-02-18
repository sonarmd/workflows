# CI/CD Architecture

## Overview

SonarMD CI/CD uses GitHub Actions with reusable workflows from this central repository. All workflows are tag-triggered for deployments, with CI running on every push/PR.

## Repository Map

| Repository | Purpose | CI | Deploy Mechanism |
|-----------|---------|-----|-----------------|
| `sonarmd/workflows` | Central reusable workflows, actions, Terraform | — | — |
| `sonarmd/frontend` | React monorepo (4 apps + shared lib) | Lint + test + build per app | S3 sync + CloudFront invalidation |
| `sonarmd/triggr_api` | Express.js API | Lint + test (4 shards) + build | Artifact → S3 → SSM → EC2 |
| `sonarmd/frontend-patient-app` | React Native mobile app | Lint + typecheck + test | EAS Build + App Store/Play Store |
| `sonarmd/triggr_misc` | Ansible playbooks | Syntax check | (legacy — SSM replaces Ansible deploys) |

## Deployment Flow

```
PR → CI (lint + test + build) → Merge to staging → auto-tag → tag triggers deploy
```

### Tag Naming Convention

`{env}-{repo}-{version}[-b{build}]`

- **Staging**: `stg-fe-1.2.3-b42` (auto-created on merge)
- **Production**: `prd-api-2.5.0` (manually created, requires approval)
- **Dev**: `dev-fe-1.2.3-b10` (auto-created on merge to dev)
- **Mobile**: `stg-mobile-1.1.0-b7`

## Secrets Management

All secrets live in 1Password (`smd_cicd` vault). A single GitHub org secret (`OP_SERVICE_ACCOUNT_TOKEN`) gives workflows access to resolve `op://` references at runtime. No other secrets are stored in GitHub.

## AWS Authentication

GitHub Actions authenticates to AWS via OIDC (OpenID Connect). No AWS access keys are stored anywhere. The IAM role `github-actions-deploy` is assumed by any workflow in the `sonarmd` org.

## Environments

| Environment | Approval Required | Instance Tags |
|------------|-------------------|---------------|
| dev | No | `APIDev` |
| stg | No | `APIStaging` |
| prd | Yes (1 reviewer) | `APIProduction` |

## Frontend Deploy (S3 + CloudFront)

1. Build all 4 apps with environment-specific `REACT_APP_ENV`
2. `aws s3 sync` static assets (7-day cache)
3. `aws s3api put-object` for `index.html` (5-min cache)
4. `aws cloudfront create-invalidation` for `/index.html` and `/asset-manifest.json`

## API Deploy (SSM)

1. Build TypeScript → `dist/`
2. Package `tar.gz` (dist + node_modules + package.json)
3. Upload artifact + generated `configuration.json` to S3
4. SSM RunCommand on each EC2 instance (serial):
   - Download from S3
   - Extract
   - Place config
   - Swap directories (keep `.old`)
   - Restart systemd
   - Health check (6 retries)
   - Auto-rollback on failure

## Mobile Deploy (EAS)

1. `eas build --profile preview` for staging
2. `eas build --profile production --auto-submit` for production
3. Auto-submits to App Store Connect + Google Play internal tracks
