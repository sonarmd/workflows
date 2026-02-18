# sonarmd/workflows

Central CI/CD infrastructure for SonarMD's GitHub Actions pipelines. Contains reusable workflows, composite actions, Terraform for AWS provisioning, and per-repo workflow templates.

## Structure

```
.github/workflows/          Reusable workflows (called by per-repo workflows)
  ci-node.yml                 CI: lint + test + build (Node.js)
  deploy-s3-cloudfront.yml    Deploy: S3 sync + CloudFront invalidation
  deploy-api-ssm.yml          Deploy: artifact → S3 → SSM → EC2
  deploy-eas-build.yml        Deploy: EAS Build (mobile)
  tag-release.yml             Auto-tag on merge to staging
  notify-slack.yml            Slack deploy notifications
  metrics-collector.yml       Record deploy metrics to S3
  metrics-report.yml          Weekly KPI summary to Slack

actions/                     Composite actions
  setup-node/                  Node.js + yarn cache
  load-secrets/                1Password secrets loader
  health-check/                HTTP health poll with backoff
  generate-config-json/        Render config template from env vars
  slack-notify/                Formatted Slack message
  detect-changed-apps/         Path filtering for frontend monorepo

terraform/                   AWS infrastructure
  main.tf                      Provider config
  oidc.tf                      GitHub OIDC provider
  iam.tf                       IAM roles + policies
  s3.tf                        Deploy artifacts + metrics buckets
  ssm.tf                       SSM document registration

ssm-documents/               AWS Systems Manager documents
  deploy-api.json              API deploy: download → extract → swap → restart → health check

templates/                   Configuration templates
  configuration.json.tpl       API config with ${VAR} placeholders

per-repo/                    Workflow templates for each repository
  frontend/                    sonarmd/frontend workflows
  triggr_api/                  sonarmd/triggr_api workflows
  frontend-patient-app/        sonarmd/frontend-patient-app workflows
  triggr_misc/                 sonarmd/triggr_misc workflows

docs/                        Documentation
  architecture.md              System architecture overview
  migration-runbook.md         Step-by-step CircleCI → GHA migration
  rollback-playbook.md         Rollback procedures per service
  secrets-inventory.md         1Password vault + secret reference
```

## Quick Start

### 1. Apply Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 2. Set GitHub Org Secret

Set `OP_SERVICE_ACCOUNT_TOKEN` as an organization-level secret in GitHub.

### 3. Set Repository Variables

Each repo needs `AWS_DEPLOY_ROLE_ARN` (from Terraform output). Frontend also needs CloudFront distribution ID variables.

### 4. Copy Workflows to Repos

Copy the appropriate `per-repo/<name>/.github/workflows/` directory to each repository.

## Deployment Flow

```
PR → CI (push/PR) → Merge to staging → auto-tag (stg-{repo}-{ver}-b{N}) → tag triggers deploy
```

Production: manually create `prd-{repo}-{version}` tag → requires GitHub Environment approval.

## Key Design Decisions

- **Tag-based deploys** (not branch-based) — safe parallel running with CircleCI during migration
- **OIDC** for AWS — no stored credentials
- **1Password** for all secrets — single `OP_SERVICE_ACCOUNT_TOKEN` resolves everything
- **Serial API deploy** — one instance at a time with auto-rollback
- **CloudFront invalidation** — improvement over current TTL-based cache expiry
- **Break-glass workflows** — manual deploy escape hatch with audit trail

## Docs

- [Architecture](docs/architecture.md)
- [Migration Runbook](docs/migration-runbook.md)
- [Rollback Playbook](docs/rollback-playbook.md)
- [Secrets Inventory](docs/secrets-inventory.md)
