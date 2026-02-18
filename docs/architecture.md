# CI/CD Architecture

## Overview

SonarMD CI/CD uses GitHub Actions as a drop-in replacement for CircleCI. Deployments are branch-triggered (same as CircleCI). Reusable workflows and composite actions live in this central repository.

## Repository Map

| Repository | Purpose | CI | Deploy Mechanism |
|-----------|---------|-----|-----------------|
| `sonarmd/workflows` | Central reusable workflows + actions | — | — |
| `sonarmd/frontend` | React monorepo (4 apps + shared lib) | Lint + test + build per app | S3 sync (GHA) |
| `sonarmd/triggr_api` | Express.js API | Lint + test (4 shards) + build | Slack → Hubot → Ansible (unchanged) |
| `sonarmd/frontend-patient-app` | React Native mobile app | Lint + typecheck + test | EAS Build (tag-triggered) |
| `sonarmd/triggr_misc` | Ansible playbooks | Syntax check | N/A |

## Deployment Flow

### Frontend

```
Push to dev/staging/master → GHA detects changed apps → builds → S3 sync → Slack notification
```

### API

```
Push to dev/staging/master → GHA builds + tests → Slack message "@r2-d2 deploy {env} {sha} {url}" → Hubot → Ansible → EC2
```

The API deploy chain (Hubot → Ansible → EC2) is unchanged. GHA replaces only the CI + artifact build + Slack notification that CircleCI previously handled.

### Mobile

```
Push tag stg-mobile-* → EAS preview build → Slack notification
Push tag prd-mobile-* → EAS production build + auto-submit → Slack notification
```

## Secrets

Stored as GitHub repository secrets (same values as CircleCI's `DevOps` context):

| Secret | Purpose |
|--------|---------|
| `AWS_ACCESS_KEY_ID` | S3 deploy for frontend |
| `AWS_SECRET_ACCESS_KEY` | S3 deploy for frontend |
| `SLACK_TOKEN` | Slack webhook for notifications |
| `EXPO_TOKEN` | EAS CLI authentication for mobile |

## Frontend S3 Bucket Mapping

| App | Dev | Stg | Prd |
|-----|-----|-----|-----|
| admin | admin.dev.sonarmd.com | admin.stg.sonarmd.com | admin.sonarmd.com |
| patient | my.dev.sonarmd.com | my.stg.sonarmd.com | my.sonarmd.com |
| provider | care.dev.sonarmd.com | care.stg.sonarmd.com | care.sonarmd.com |
| seat | seat.dev.sonarmd.com | seat.stg.sonarmd.com | seat.sonarmd.com |

## S3 Cache Strategy

- Static assets (JS, CSS, images): `max-age=604800` (7 days) — content-hashed filenames
- `index.html`: `max-age=300` (5 minutes) — references change on each deploy
- `asset-manifest.json`: `max-age=300` (5 minutes)
