# SonarMD CI/CD Pipeline

Every repo that ships to production uses the same two-file setup: a CI workflow stub and a CD wrapper. The platform owns the logic. The repo owns its build, tests, and deploy config.

---

## How it works

```
PR → CI (lint + test + build + sign) → merge → CD (tag + release + @r2-d2) → Ansible deploy
```

### Tag format

```
{stg|prd}-{identifier}-b{run_number}
```

Examples: `prd-api-b188`, `stg-fe-b44`, `prd-mobile-b12`

No semver. Build number is monotonically incrementing across all runs of the workflow — it goes up forever.

- `stg` tags are created on merge to `release/*`
- `prd` tags are created on merge to `master` or `main`

---

## What goes in each repo

### 1. `.github/workflows/cd.yml` — thin wrapper

```yaml
name: CD

on:
  push:
    branches: [master, 'release/**']

concurrency:
  group: cd-${{ github.ref_name }}
  cancel-in-progress: false

jobs:
  cd:
    uses: sonarmd/workflows/.github/workflows/cd.yml@<sha>
    with:
      repo-identifier: api   # api | fe | mobile | cdk
    secrets:
      OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN_AGORA }}
```

That's it. One input. Everything else is driven by the repo's own files.

**Always pin to a commit sha, not `@main`.** The CD pipeline touches production. Floating refs are not acceptable here.

---

### 2. `.github/workflows/ci.yml` — filled-out stub

```yaml
name: CI

on:
  pull_request:
    branches: [master, 'release/**']
  merge_group:
    branches: [master, 'release/**']

concurrency:
  group: ci-${{ github.event.pull_request.number || github.ref_name }}
  cancel-in-progress: true

permissions:
  contents: read
  id-token: write

env:
  NODE_OPTIONS: '--max-old-space-size=4096'   # tune per repo

jobs:
  ci:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    services:
      mongo:                          # remove if not needed
        image: mongo:8.0
        ports:
          - 27017:27017
        options: >-
          --health-cmd "mongosh --eval 'db.adminCommand({ping:1})'"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: sonarmd/workflows/actions/ping-slack@<sha>
        with:
          webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
          status: started
          app: my-repo

      - uses: actions/checkout@<sha>

      - uses: sonarmd/workflows/actions/setup-node@<sha>

      # ── Repo-specific setup ──────────────────────────────────────────────
      # Add whatever your project needs: apt packages, docker containers, etc.
      - run: sudo apt-get update -qq && sudo apt-get install -y graphicsmagick

      # ── Repo owns these steps ────────────────────────────────────────────
      - run: yarn lint
      # - run: yarn typecheck    # optional — uncomment if you have a typecheck script
      - run: yarn build
      - name: Test
        env:
          LOG_LEVEL: none
          TZ: utc
        run: yarn test:ci --reporters=jest-junit

      # ── Platform owns everything below ──────────────────────────────────
      - uses: sonarmd/workflows/actions/ci-sign@<sha>
        if: always()
        with:
          test_report_path: junit.xml
          build_output_dir: dist
        env:
          OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN_AGORA }}

      - uses: sonarmd/workflows/actions/ping-slack@<sha>
        if: always()
        with:
          webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
          status: ${{ job.status }}
          app: my-repo
```

The "Repo owns" section is the only thing you edit per-repo. Everything above and below is standard.

---

### 3. `deploy.json` — deploy config (committed to repo)

Defines every deployable unit in this repo. Ansible reads this from the release artifact to know what to do.

```json
{
  "app": "my-repo",
  "bundles": [
    {
      "name": "api",
      "target": "ec2",
      "path": "dist",
      "hosts": ["api-{env}.sonarmd.net"]
    },
    {
      "name": "my-lambda",
      "target": "lambda",
      "path": "lambdas/my-lambda/artifact",
      "hosts": ["my-lambda-{env}"]
    }
  ]
}
```

**`{env}` is a placeholder** — the CD workflow substitutes the actual environment (`stg` or `prd`) before packaging. Ansible receives a fully resolved deploy.json.

#### Target types

| `target` | What Ansible does | Required fields |
|----------|-------------------|-----------------|
| `ec2` | Rolling deploy via SSH | `hosts`, `path` |
| `lambda` | Zip + update function code | `hosts`, `path` |
| `s3` | Sync to S3 + CloudFront invalidation | `hosts` (bucket name), `path` |
| `eas` | EAS cloud build via CLI | `eas_profile` |
| `cdk` | CloudFormation stack update | `hosts` (stack name), `path` |

`hosts` values match the `Hostname` AWS tag on the target resource (without the domain). The CD workflow resolves `{env}` at build time.

---

## What the platform provides

### CI actions (`actions/`)

| Action | What it does |
|--------|-------------|
| `setup-node` | Installs Node from `package.json` volta/engines, caches yarn deps |
| `ci-sign` | Verifies test report has real tests, generates CycloneDX SBOM, uploads evidence, attests with Sigstore |
| `ping-slack` | CI-focused Slack notifier — fires on start, success, and failure with branch/commit/actor context |
| `slack-notify` | Deploy-focused Slack notifier — fires with env/version/actor context |
| `load-secrets` | 1Password secret injection via service account |

### CD workflow (`workflows/cd.yml`)

1. Infer env from branch (`release/*` → stg, `master` → prd)
2. Build tag: `{env}-{identifier}-b{run_number}`
3. Get GitHub App token from 1Password
4. Checkout repo
5. Run `yarn build` (repo provides this)
6. Resolve `deploy.json` — substitute `{env}`, validate it exists
7. Package `release.tar.gz` — `deploy.json + package.json + dist/ + cdk.out/` (whatever exists)
8. Create git tag + GitHub release (pre-release for stg, full release for prd)
9. Notify `#ops`: `@r2-d2 {env} {identifier} {tag} {artifact_url}` → triggers Ansible

---

## Prerequisites for a new repo

1. **Install the SonarMD deploy GitHub App** on the repo
2. **Add required secrets** to the repo:
   - `SLACK_WEBHOOK_URL`
   - `OP_SERVICE_ACCOUNT_TOKEN_AGORA` (mapped to `OP_SERVICE_ACCOUNT_TOKEN` in the CD wrapper — see stub above)
3. **Add `deploy.json`** — define the units this repo deploys
4. **Add `ci.yml`** and **`cd.yml`** from the stubs above
5. **Ensure `yarn build` builds everything** — all lambda bundles, all output — in one command
6. **Ensure `yarn test:ci` produces `junit.xml`** — `ci-sign` gate rejects builds without it

---

## Lambda bundles

Lambda functions are built as part of `yarn build` and land under `dist/lambdas/{name}/`. The deploy.json `bundlePath` points to that subdirectory. Ansible zips it and deploys.

For Python lambdas with heavy deps (pandas, sklearn, etc.): use a Lambda Layer or container image. The zip limit is 50MB uncompressed. A Lambda Layer lets you ship deps separately and only update code. Define a separate `target: lambda-layer` unit in deploy.json when you get there.

---

## Maintenance

When you update an action or workflow in this repo, **update the pinned sha** in every caller. The sha is your version pin. `@main` is not a version.

To find all callers of an action:
```bash
grep -r "sonarmd/workflows/actions/ci-sign@" ../*/
```

To find all cd.yml thin wrappers:
```bash
grep -r "sonarmd/workflows/.github/workflows/cd.yml@" ../*/
```
