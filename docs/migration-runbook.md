# Migration Runbook: CircleCI → GitHub Actions

## Prerequisites

- [ ] `sonarmd/workflows` repo created with all workflows and actions
- [ ] GitHub secrets set: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `SLACK_TOKEN`
- [ ] `EXPO_TOKEN` secret set on `frontend-patient-app` repo

## Phase 1: Frontend CI

1. Copy `per-repo/frontend/.github/workflows/ci.yml` to `sonarmd/frontend`
2. Open a PR to staging
3. Verify GHA CI runs alongside CircleCI on the same PR
4. Compare: same tests pass/fail, timing comparable, Cypress works
5. Merge to staging — both CI systems run (no conflict)

### Validation

```bash
gh run list --repo sonarmd/frontend --workflow ci.yml --limit 5
```

### Rollback

Delete `.github/workflows/ci.yml` from the repo. CircleCI continues unaffected.

---

## Phase 2: Frontend Deploy

### Setup

1. Copy `per-repo/frontend/.github/workflows/deploy.yml` to `sonarmd/frontend`
2. Set repository secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `SLACK_TOKEN`

### Dev First

1. Push a change to `dev` branch
2. Verify GHA deploy workflow triggers
3. Verify S3 content matches CircleCI output
4. Verify Slack notification fires

### Staging + Production

1. Disable CircleCI deploy jobs one environment at a time
2. Push to staging — verify GHA deploys correctly
3. Push to master — verify production deploy

---

## Phase 3: API CI

1. Copy `per-repo/triggr_api/.github/workflows/ci.yml` to `sonarmd/triggr_api`
2. Verify:
   - 4-shard test parallelism works with MongoDB service container
   - GraphicsMagick installs correctly
   - Test timing is comparable to CircleCI

---

## Phase 4: API Deploy

1. Copy `per-repo/triggr_api/.github/workflows/deploy.yml` to `sonarmd/triggr_api`
2. Set `SLACK_TOKEN` secret
3. Push to `dev` — verify `@r2-d2 deploy dev {sha} {url}` Slack message fires
4. Verify Hubot picks up the GHA artifact URL (may need Hubot update if it parses CircleCI URLs)
5. Repeat for staging and master
6. Disable CircleCI deploy jobs

**Note**: The Slack message format is `@r2-d2 deploy {env} {sha} {artifact_url}`. The artifact URL will now point to a GHA run instead of CircleCI. Hubot may need a small update to handle this.

---

## Phase 5: Mobile App

1. Copy `per-repo/frontend-patient-app/.github/workflows/` to `sonarmd/frontend-patient-app`
2. Set `EXPO_TOKEN` and `SLACK_TOKEN` secrets
3. Test preview build: `git tag stg-mobile-test-0.0.1 && git push origin stg-mobile-test-0.0.1`
4. Test production build + auto-submit

---

## Phase 6: Cleanup

- [ ] Remove `.circleci/` from all repos
- [ ] Decommission CircleCI project connections
- [ ] Update all repo READMEs

---

## Safety: Parallel Running

Both systems coexist safely during migration:

- **CircleCI**: branch-based triggers (existing)
- **GitHub Actions**: branch-based triggers (new, but different workflow files)

To avoid double-deploys during the transition, disable CircleCI deploy jobs one at a time before enabling the corresponding GHA deploy workflow.
