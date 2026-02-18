# sonarmd/workflows

Central CI/CD infrastructure for SonarMD's GitHub Actions pipelines. Drop-in replacement for CircleCI — same branch-based triggers, same deploy patterns, same secrets approach.

## Structure

```
.github/workflows/          Reusable workflows (called by per-repo workflows)
  ci-node.yml                 CI: lint + test + build (Node.js)
  deploy-s3-cloudfront.yml    Deploy: S3 sync + optional CloudFront invalidation
  deploy-eas-build.yml        Deploy: EAS Build (mobile)
  tag-release.yml             Auto-tag on merge (for future use)
  notify-slack.yml            Slack deploy notifications

actions/                     Composite actions
  setup-node/                  Node.js via Volta detection + yarn cache
  detect-changed-apps/         Path filtering for frontend monorepo
  slack-notify/                Formatted Slack message

per-repo/                    Workflow templates for each repository
  frontend/                    sonarmd/frontend workflows
  triggr_api/                  sonarmd/triggr_api workflows
  frontend-patient-app/        sonarmd/frontend-patient-app workflows
  triggr_misc/                 sonarmd/triggr_misc workflows

docs/                        Documentation
  architecture.md              System architecture overview
  migration-runbook.md         Step-by-step CircleCI → GHA migration
```

## GitHub Secrets Required

Set these as repository secrets (same values as CircleCI's `DevOps` context):

| Secret | Repos | Purpose |
|--------|-------|---------|
| `AWS_ACCESS_KEY_ID` | frontend | AWS deploy credentials |
| `AWS_SECRET_ACCESS_KEY` | frontend | AWS deploy credentials |
| `SLACK_TOKEN` | frontend, triggr_api | Slack webhook token |
| `EXPO_TOKEN` | frontend-patient-app | Expo/EAS CLI token |

## Copy Workflows to Repos

Copy the appropriate `per-repo/<name>/.github/workflows/` directory to each repository's `.github/workflows/`.

## How It Works

### Frontend (`sonarmd/frontend`)

**CI** — Runs on every push and PRs to staging/master:
- Detects which apps changed (admin, patient, provider, seat, shared)
- Installs deps + builds shared lib (cached across jobs)
- Runs per-app unit tests + Cypress (only for changed apps)
- Lints the full codebase

**Deploy** — Runs on push to `dev`, `staging`, `master`:
- Detects changed apps via path filtering
- Builds each changed app with environment-specific vars
- Syncs to S3 (7-day cache for assets, 5-min cache for index.html)
- Notifies Slack

### API (`sonarmd/triggr_api`)

**CI** — Runs on every push and PRs to staging/master:
- Lints, runs tests across 4 shards with MongoDB service container, builds

**Deploy** — Runs on push to `dev`, `staging`, `master`:
- Runs lint + test + build
- Packages build artifact (tar.gz) and uploads as GHA artifact
- Sends `@r2-d2 deploy {env} {sha} {artifact_url}` to Slack (same pattern as current `slack-deploy.sh`)
- Hubot + Ansible handle the actual EC2 deployment (unchanged)

### Mobile (`sonarmd/frontend-patient-app`)

**CI** — Runs on every push and PRs:
- Lint + typecheck + test (Node 22)

**EAS Builds** — Tag-triggered:
- `stg-mobile-*` tags trigger preview builds
- `prd-mobile-*` tags trigger production builds with auto-submit

### Misc (`sonarmd/triggr_misc`)

**CI** — Ansible playbook syntax check on push/PR
