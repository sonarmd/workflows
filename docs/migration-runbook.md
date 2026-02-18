# Migration Runbook: CircleCI → GitHub Actions

## Prerequisites

- [ ] `sonarmd/workflows` repo created with all workflows and actions
- [ ] Terraform applied (OIDC provider, IAM roles, S3 buckets, SSM document)
- [ ] SSM Agent installed on all EC2 instances
- [ ] 1Password `smd_cicd` vault created with Service Account
- [ ] `OP_SERVICE_ACCOUNT_TOKEN` set as GitHub org secret
- [ ] GitHub Environments (dev, stg, prd) created with protection rules
- [ ] All composite actions tested locally / in dry-run

## Phase 1: Frontend CI (Week 2)

### Steps

1. Copy `per-repo/frontend/.github/workflows/ci.yml` to `sonarmd/frontend`
2. Open PR to staging
3. Verify GHA CI runs alongside CircleCI on the same PR
4. Compare:
   - Do the same tests pass/fail?
   - Is timing comparable?
   - Are Cypress tests working?
5. Merge to staging — both CI systems should run

### Validation

```bash
# Compare test results
gh run list --repo sonarmd/frontend --workflow ci.yml --limit 5
```

### Rollback

Delete `.github/workflows/ci.yml` from the repo. CircleCI continues unaffected.

---

## Phase 2: Frontend Deploy (Weeks 3-4)

### Dev First

1. Copy `deploy-dev.yml` and `auto-tag.yml` to `sonarmd/frontend`
2. Set repository variables:
   - `AWS_DEPLOY_ROLE_ARN` — from Terraform output
3. Create a test tag: `git tag dev-fe-test-0.0.1 && git push origin dev-fe-test-0.0.1`
4. Verify:
   - GHA workflow triggers
   - Build completes
   - S3 content matches CircleCI output
   - Slack notification fires

### Staging

1. Copy `deploy-stg.yml`
2. Set CloudFront distribution ID variables: `CF_DIST_ADMIN_STG`, `CF_DIST_PATIENT_STG`, `CF_DIST_PROVIDER_STG`, `CF_DIST_SEAT_STG`
3. **Disable CircleCI staging deploy**: In CircleCI, remove the staging deploy job filter
4. Merge a PR to staging — auto-tag should create `stg-fe-*` tag → GHA deploys
5. Verify CloudFront invalidation works (check `index.html` updates within 60s)

### Production

1. Copy `deploy-prd.yml`
2. Set `CF_DIST_*_PRD` variables
3. Disable CircleCI production deploy
4. Manually create `prd-fe-*` tag → verify approval gate + deploy

---

## Phase 3: API CI (Week 5)

1. Copy `per-repo/triggr_api/.github/workflows/ci.yml`
2. Verify:
   - 4-shard test parallelism works with MongoDB service container
   - GraphicsMagick installs correctly
   - Test timing is comparable to CircleCI

---

## Phase 4: API Deploy (Weeks 6-7)

### Critical: Config Generation Verification

Before deploying anywhere, verify the configuration.json output matches Ansible:

```bash
# Generate config from 1Password (locally)
# Compare with: ansible-vault decrypt + template render
diff <(generated_config) <(ansible_rendered_config)
```

Every field must match. Pay special attention to:
- Boolean values (`true`/`false` vs `True`/`False`)
- JSON arrays/objects
- Empty string defaults

### Dev First

1. Copy `deploy-dev.yml`, `auto-tag.yml`
2. Migrate secrets from Ansible Vault to 1Password `smd_cicd/API/dev/config-secrets`
3. Deploy to dev via tag
4. Verify API starts and `/health` returns 200

### Staging

1. Copy `deploy-stg.yml`
2. Migrate stg secrets to 1Password
3. Disable CircleCI stg deploy
4. Deploy — verify serial deployment (one instance at a time)
5. Verify health checks pass on each instance
6. Verify auto-rollback works (intentionally break health check)

### Production

1. Copy `deploy-prd.yml`
2. Migrate prd secrets
3. Disable CircleCI prd deploy
4. Deploy with careful monitoring
5. Verify Slack notifications for success/failure

---

## Phase 5: Mobile App (Week 8)

1. Copy all `frontend-patient-app` workflows
2. Set up EXPO_TOKEN in 1Password
3. Test preview build
4. Test production build + auto-submit

---

## Phase 6: Cleanup (Week 9)

- [ ] Remove `.circleci/` from all repos
- [ ] Decommission CircleCI project connections
- [ ] Copy `break-glass.yml` to all repos
- [ ] Decommission Hubot deploy bot on bastion
- [ ] Archive Ansible deploy playbooks (don't delete — keep for reference)
- [ ] Update all repo READMEs with new CI/CD documentation

---

## Safety: Parallel Running

During migration, both systems coexist safely:
- **CircleCI**: branch-based triggers (push to staging/master)
- **GitHub Actions**: tag-based triggers (push tags matching patterns)

No risk of double-deploy. Disable CircleCI deploys one environment at a time by removing branch filters from the CircleCI config.
