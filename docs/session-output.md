# Session Output — Complete State + Recommendations

Everything from this session in one place.

---

## 1. CURRENT REPO STATE (sonarmd-workflows)

### What exists now in .github/workflows/

All original workflows restored, plus two new additive ones:

| File | Status | Notes |
|------|--------|-------|
| ci.yml | ORIGINAL | Universal reusable CI (multi-job: setup/static-analysis/test/build/gate) |
| cd.yml | ORIGINAL | CD pipeline (autotag/artifact/release/notify/cut-branch) |
| ci-core.yml | NEW | Next-gen CI (single-job, shell-block model) |
| cd-core.yml | NEW + PATCHED | Next-gen CD (platform-owned identifier, release branch lifecycle) |
| gate.yml | ORIGINAL | Merge queue evidence verification |
| break-glass.yml | ORIGINAL | Emergency recovery |
| build-gate.yml | ORIGINAL | Build validation gate |
| deploy-gate.yml | ORIGINAL | Deploy prerequisites gate |
| static-analysis-gate.yml | ORIGINAL | Lint evidence gate |
| test-gate.yml | ORIGINAL | Test evidence gate |
| preflight.yml | ORIGINAL | Circuit breaker for PR CI |
| auto-tag.yml | ORIGINAL | Semver auto-tagging |
| tag-release.yml | ORIGINAL | Tag + release creation |
| deploy.yml | ORIGINAL | Deploy notifier |
| deploy-api-ssm.yml | ORIGINAL | SSM deployment |
| deploy-ecs.yml | ORIGINAL | ECS deployment |
| deploy-eas-build.yml | ORIGINAL | EAS/Expo build |
| deploy-s3-cloudfront.yml | ORIGINAL | S3+CloudFront deploy |
| manual-deploy.yml | ORIGINAL | Manual tag/version resolution |
| notify-slack.yml | ORIGINAL | Slack notifications |
| metrics-collector.yml | ORIGINAL | Deploy metrics |
| metrics-report.yml | ORIGINAL | Weekly metrics report |
| dike-seal.yml | ORIGINAL | Governance (Agora) |
| dike-verify.yml | ORIGINAL | Governance (Agora) |

### What exists now in actions/

All original actions restored, plus 14 new additive ones:

**Original (restored):**
- ci-sign, detect-changed-apps, ci-breaker, ping-slack, slack-notify
- health-check, generate-config-json, setup-node, checkout-agora, load-secrets

**New (additive):**
- timeout-handler, start-monitoring, open-ci, close-ci
- run-shell-block, validate-release-contract, checksum-generator
- sbom-generator, bundle-release, tagging-and-classification
- release-note-maintainer, create-tag-release, notify-slack, product-documentation

### New files added this session

- `.github/repo-identity.yml` — platform-owned identifier mapping
- `schemas/deploy.schema.json` — deploy.json JSON Schema
- `docs/platform-spec.md` — platform specification
- `config/` — attempted but sandbox blocks this path

### Removed this session

- `archive/` directory (was created then removed — originals restored instead)
- `per-repo/*/deploy.json` (pollution — consuming repo artifacts)
- `per-repo/*/.github/workflows/cd.yml` (pollution — consuming repo artifacts)

---

## 2. PLATFORM-OWNED IDENTIFIER MAPPING

File: `.github/repo-identity.yml`

```yaml
repo_identifier_map:
  triggr_api: api
  frontend: fe
  frontend-patient-app: mobile
  triggr_misc: infra
  infra-cdk: cdk
```

**Rule:** CD derives identifier from this mapping using `github.repository.name`. Repos CANNOT control their deploy identity. If `deploy.json.identifier` exists and disagrees, CD fails.

---

## 3. CD-CORE.YML — CURRENT STATE (PATCHED)

### Tag format
```
{env}-{identifier}-v{version}-b{build}
```
Examples: `stg-api-v1.0.0-b1`, `prd-api-v1.0.0-b2`

### Version resolution
- **Staging**: parsed from branch name `release/v1.0.0` → `1.0.0`
- **Production**: derived from the merged release branch (4-method detection):
  1. GitHub PR event source branch (`github.event.pull_request.head.ref`) — preferred
  2. Merge commit message parsing — fallback
  3. Second parent branch inspection — fallback
  4. Merged branch containment — last resort
- **NOT from package.json**
- **NOT from "latest staging tag"**

### Build number
- Per-repo + per-version, computed from existing git tags
- Shared across stg and prd (one sequence per identifier+version)
- `stg-api-v1.0.0-b1` → `prd-api-v1.0.0-b2` → `stg-api-v1.0.0-b3`
- Tags explicitly fetched (`git fetch --tags --force`) before computation
- Tag collision guard: checks for existing tag before push

### GitHub Release
- Staging: `--draft --prerelease`
- Production: full release (no flags)

### Next release branch
- After successful production CD
- Bumps minor, zeros patch: `v1.0.0` → `release/v1.1.0`
- Explicitly created from `origin/master`
- Skips if branch already exists

### Slack contract
```
deploy <env> <identifier> <deploy_tag> <artifact_url>
```
Example: `deploy stg api stg-api-v1.0.0-b1 https://api.github.com/repos/sonarmd/triggr_api/releases/tags/stg-api-v1.0.0-b1`

---

## 4. DEPLOY.JSON SCHEMA

File: `schemas/deploy.schema.json`

```json
{
  "app": "triggr-api",
  "identifier": "api",
  "build_root": "dist",
  "bundles": [
    {
      "name": "api",
      "path": ".",
      "target": "ec2",
      "hosts": {
        "api-primary": "api-01.${env}.internal"
      }
    }
  ]
}
```

Rules:
- `app` — required
- `identifier` — required, must match platform mapping or CD fails
- `build_root` — optional, default `dist`
- `bundles` — required, min 1
- `bundles[].target` — enum: `s3`, `ec2`, `eas`, `cdk`, `lambda`, `fargate`
- `bundles[].hosts` — object (label → Ansible inventory match key), NOT array
- Only `${env}` template variable allowed
- `additionalProperties: false`

---

## 5. RELEASE LIFECYCLE

```
1. Create release/v1.0.0 branch
2. Feature branches → PR into release/v1.0.0
3. Merge to release branch → CD creates stg-api-v1.0.0-b1 (draft prerelease)
4. PR from release/v1.0.0 → master
5. Merge to master → CD creates prd-api-v1.0.0-b2 (full release)
6. Auto-create release/v1.1.0 from master
```

---

## 6. STAR-CONFIG REGISTRY PROBLEM (CONFIRMED)

### Root cause
Global `~/.npmrc` contains:
```
@sonarmd:registry=https://npm.pkg.github.com
```
This redirects ALL `@sonarmd/*` package resolutions to GitHub Packages, requiring auth for every `yarn install` everywhere.

### Evidence
- `infra-cdk/.npmrc` — hardcoded `gho_` token (security violation)
- `agora-dev-tools/.npmrc` — requires `${GITHUB_TOKEN}` env var
- `triggr_api`, `frontend`, `frontend-patient-app` — no `.npmrc`, can't install
- `@sonarmd/star-config` on public npm — HTTP 404 (not published there)
- `star-config` has no `bin` field — `npx @sonarmd/star-config` won't work
- `publishConfig.registry` points at `https://npm.pkg.github.com`

### Recommendation: Publish to public npmjs.org

The package is eslint/prettier/tsconfig configs. Zero business logic. Publishing publicly eliminates all auth friction.

### Changes needed in star-config repo

**package.json:**
```json
{
  "publishConfig": {
    "registry": "https://registry.npmjs.org",
    "access": "public"
  },
  "bin": {
    "star-config": "./bin/cli.mjs"
  }
}
```

**star-config/.npmrc:** Delete the scope redirect line or delete the file.

**publish.yml:**
```yaml
- uses: actions/setup-node@v4
  with:
    node-version: '22'
    registry-url: 'https://registry.npmjs.org'
    cache: 'yarn'

- run: npm publish --access public
  env:
    NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```

**New file: `bin/cli.mjs`** — enables `npx @sonarmd/star-config`:
```javascript
#!/usr/bin/env node
import { argv } from 'node:process';
const cmd = argv[2] || 'setup';
if (cmd === 'setup') await import('../repo-setup/install.mjs');
else if (cmd === 'hooks') await import('../husky/install.mjs');
else { console.log('Usage: npx @sonarmd/star-config [setup|hooks]'); process.exit(1); }
```

### Cleanup needed elsewhere

1. Remove `@sonarmd:registry=https://npm.pkg.github.com` from `~/.npmrc`
2. Delete `infra-cdk/.npmrc` (hardcoded token)
3. Delete `agora-dev-tools/.npmrc` (no longer needed)
4. Claim `@sonarmd` org on npmjs.org
5. Create `NPM_TOKEN` org secret in GitHub for publish workflow

### Migration
1. Claim @sonarmd on npmjs.org
2. Update star-config for public npm (package.json + publish.yml + .npmrc)
3. Add bin entry
4. Publish v4.0.0 to public npm
5. Remove global .npmrc scope redirect
6. Remove consumer .npmrc files
7. All future `yarn add -D @sonarmd/star-config` just works, no auth

---

## 7. WHAT REMAINS UNCHANGED

- Ansible — not touched, not redesigned
- deploy_tag — authoritative git tag
- artifact_url — GitHub Release metadata/API URL
- Slack contract — `deploy <env> <identifier> <deploy_tag> <artifact_url>`
- ci-sign + gate evidence chain — restored and intact
- detect-changed-apps — restored and intact
- All original workflows — restored to committed state
- All original actions — restored to committed state
- per-repo/ CI wrappers — restored to committed state (originals)

---

## 8. WHAT IS NOT YET DONE

- [ ] Claim @sonarmd on npmjs.org
- [ ] Update star-config for public npm publish
- [ ] Add bin entry to star-config
- [ ] Publish star-config v4.0.0 to public npm
- [ ] Remove global .npmrc scope redirect
- [ ] Clean consumer .npmrc files
- [ ] Build `verify:platform` command in star-config
- [ ] Ansible deployment cleanup (separate task, not started)
- [ ] Push sonarmd-workflows changes to remote
- [ ] Open PR for sonarmd-workflows changes

---

## 9. GIT STATUS (sonarmd-workflows)

Branch: `feature/cd-reusable-workflow` (2 commits ahead of origin + unstaged changes)

New untracked files (additive only — no deletions, no modifications to originals):
- `.github/workflows/cd-core.yml`
- `.github/workflows/ci-core.yml`
- `.github/repo-identity.yml`
- `schemas/deploy.schema.json`
- `docs/platform-spec.md`
- 14 new actions under `actions/`
