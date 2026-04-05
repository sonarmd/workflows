# CI/CD — Final Architecture

This document is the source of truth for the SonarMD CI/CD pipeline. Everything not described here gets removed.

---

## Principles

- **sonarmd/workflows is the source of truth.** All shared logic lives here. Repos only define what is unique to them.
- **CI and CD are separate concerns.** CI runs on PR. CD runs on merge.
- **CD never re-runs a build.** It uses the artifact produced by the CI run on the exact commit being merged. Rebase FF-only merges are enforced so the tip of the target branch after merge IS the commit that ran CI.
- **Slack `#ops` receives a notification on start and on success/fail for every workflow run across every repo.**
- **Every artifact is signed with the commit hash and accompanied by a SBOM.** No unsigned artifacts are ever released.
- **deploy.json in each repo is the deployment contract.** Ansible reads it. Hubot reads it. Nothing else defines where a bundle goes.

---

## Repository Structure — sonarmd/workflows

```
sonarmd/workflows
├── .github/
│   └── workflows/
│       ├── ci.yml               # Reusable CI stub (workflow_call)
│       ├── cd.yml               # Reusable CD workflow (workflow_call)
│       └── agora/
│           ├── dike-verify.yml  # Zero-trust PR enforcement (stays, moved here)
│           └── dike-seal.yml    # Post-merge attestation sealing (stays, moved here)
├── actions/
│   ├── auto-tag/                # Creates and pushes a git release tag
│   ├── ci-sign/                 # Signs artifacts with commit SHA via 1Password
│   ├── sbom-generator/          # Generates CycloneDX SBOM for the artifact
│   ├── github-release/          # Creates GitHub Release from CI artifact
│   ├── ping-slack/              # Sends formatted Slack message to #ops
│   ├── setup-node/              # (existing — keep)
│   ├── load-secrets/            # (existing — keep)
│   ├── detect-changed-apps/     # (existing — keep)
│   └── checkout-agora/          # (existing — keep)
└── CICD_FINALFINAL.md           # This file
```

**Remove from sonarmd/workflows:**
- `.github/workflows/build-gate.yml`
- `.github/workflows/deploy-api-ssm.yml`
- `.github/workflows/deploy-eas-build.yml`
- `.github/workflows/deploy-ecs.yml`
- `.github/workflows/deploy-gate.yml`
- `.github/workflows/deploy-s3-cloudfront.yml`
- `.github/workflows/gate.yml`
- `.github/workflows/metrics-collector.yml`
- `.github/workflows/metrics-report.yml`
- `.github/workflows/notify-slack.yml` → replaced by `actions/ping-slack/`
- `.github/workflows/static-analysis-gate.yml`
- `.github/workflows/tag-release.yml`
- `.github/workflows/test-gate.yml`

---

## Reusable Actions

### `actions/ping-slack/`

Sends a formatted Slack message to `#ops`. Used by both CI and CD on start, success, and failure.

**Inputs:**
```
status:      success | failure | started
app:         Repository/app name (e.g. triggr_api, frontend)
environment: dev | stg | prd  (optional)
tag:         Git tag or SHA
message:     Full message string (for hubot deploy ping, pass the formatted command)
```

**Behavior:** Posts to `#ops` via `SLACK_WEBHOOK_URL`. If `message` is provided, posts it verbatim (used for Hubot trigger). Otherwise formats a standard status block.

---

### `actions/auto-tag/`

Creates and pushes a git tag to the current commit.

**Inputs:**
```
repo-short:   Short repo identifier (api, fe, mobile)
environment:  dev | stg | prd  (derived from branch: release/** = stg, master/main = prd)
version:      Semver from package.json
run-number:   ${{ github.run_number }}
```

**Output:** `tag` — the created tag string, e.g. `prd-api-1.4.2-b188`

**Tag format:** `{env}-{repo-short}-{version}-b{run_number}`

---

### `actions/ci-sign/`

Signs one or more artifact files using the commit SHA as the identity anchor. Uses 1Password attestation via `OP_SERVICE_ACCOUNT_TOKEN`.

**Inputs:**
```
artifacts:    Glob or path to file(s) to sign
commit-sha:   ${{ github.sha }}
```

**Output:** Signed attestation bundle uploaded as `ci-evidence` artifact. Includes original artifact + `.sig` + SBOM.

---

### `actions/sbom-generator/`

Generates a CycloneDX SBOM for the build output.

**Inputs:**
```
artifact-path:  Path to build output directory or tarball
format:         cyclonedx-json (default)
output:         Output file path (default: sbom.json)
```

**Output:** `sbom.json` written to `output` path.

---

### `actions/github-release/`

Creates a GitHub Release (or prerelease) using the `ci-evidence` artifact produced by the CI run on the current commit.

**Inputs:**
```
tag:          The tag to attach the release to (output of auto-tag)
prerelease:   true | false  (true for release/**, false for master/main)
artifact:     Name of the CI artifact to attach (default: ci-evidence)
token:        GitHub token with contents:write
```

**Behavior:**
1. Finds the most recent workflow run on `${{ github.sha }}` that produced a `ci-evidence` artifact.
2. Downloads `ci-evidence`, renames the tarball to `release.tar.gz`.
3. Creates the GitHub Release at `tag` with `release.tar.gz` attached.
4. Sets prerelease flag accordingly.

---

## Reusable Workflows

### `ci.yml` — CI Stub

**Trigger:** `workflow_call`

**What the platform provides (automatic, non-negotiable):**
- SBOM generation via `sbom-generator` action on the build output
- Artifact signing via `ci-sign` action on all outputs
- Upload of `ci-evidence` artifact (lint output + test results + build tarball + SBOM + signatures)
- Slack ping to `#ops` on start and on success/fail

**What each repo fills in:**

```yaml
# Each repo provides these three job implementations:

jobs:
  setup:
    # Install system deps, language runtimes, package managers.
    # e.g.: apt install graphicsmagick, yarn install, npm ci

  lint:
    # Run linter. Produce lint output as artifact.
    # e.g.: yarn lint, eslint, ruff

  test:
    # Run test suite. Produce JUnit XML as artifact.
    # e.g.: yarn test:ci, pytest, mocha

  build:
    # Produce the deployable artifact.
    # Output must land in a known path (configured per-repo).
    # e.g.: yarn build, tsc, npm run build
    # For frontend-patient-app: eas build --local (sanity check only, not the deploy build)
```

**The platform wraps these jobs** — it calls them in order, enforces they pass, then runs SBOM + sign + upload. Repos do not need to call those steps themselves.

---

### `cd.yml` — Universal CD

**Trigger:** `workflow_call`  
**Called by:** each repo's ~10-line `cd.yml` shim on push to `release/**` or `master/main`

**Inputs (passed by each repo's shim):**
```
app:           App name (triggr_api, frontend, patient-mobile)
repo-short:    Short tag prefix (api, fe, mobile)
slack-project: Display name for Slack message
deploy-json:   Path to deploy.json in the repo (default: deploy.json)
node-version:  Node version (for reading package.json version)
```

**Secrets (passed through):**
```
OP_SERVICE_ACCOUNT_TOKEN_AGORA
SLACK_WEBHOOK_URL
GH_RELEASE_TOKEN
```

**Jobs (in order):**

```
1. resolve-env
   - Derives environment from branch:
       release/**  → stg
       master/main → prd
   - Reads version from package.json at the merged commit
   - Outputs: env, version

2. check-ci-artifact
   - Queries GitHub Actions API for workflow runs on ${{ github.sha }}
   - Looks for a completed successful run that produced a ci-evidence artifact
   - Outputs: artifact-found (true | false), artifact-id

3. ci-fallback  [runs only if artifact-found == false]
   - Calls the reusable ci.yml workflow_call inline (same jobs: setup, lint, test, build,
     sbom, sign, upload ci-evidence)
   - Posts to #ops: "No CI artifact found for {sha} — running CI now before releasing"
   - If this job fails, CD aborts and pings #ops with failure. No release is created.

4. auto-tag  [runs after check-ci-artifact or ci-fallback, whichever ran]
   - Calls actions/auto-tag with env + version + run-number
   - Outputs: tag (e.g. prd-api-1.4.2-b188)

5. github-release
   - Calls actions/github-release
   - Uses ci-evidence artifact from step 2 (existing run) or step 3 (fallback run)
   - Creates GitHub Release at the new tag
   - prerelease = true if env == stg, false if env == prd

6. ping-slack
   - Calls actions/ping-slack with a Hubot deploy command for each bundle in deploy.json
   - Message format (one ping per bundle):
       @r2-d2 {app} {bundle-name} {env} {tag} {artifact_url}
   - artifact_url = GitHub API URL for the release just created
   - Pings #ops
```

**On failure at any step:** calls `ping-slack` with `status: failure`.

---

## Per-Repo Structure

Each repo contains exactly these files and nothing else related to CI/CD:

```
.github/
└── workflows/
    ├── ci.yml     # Repo's implementation of the CI stub
    └── cd.yml     # ~10-line shim calling sonarmd/workflows cd.yml
deploy.json        # Deployment contract (see below)
```

No `auto-tag.yml`. No `draft-release.yml`. No `ping-slack.yml`. No `break-glass.yml` unless the repo specifically needs emergency deploy capability (mobile only).

---

### `ci.yml` (per-repo)

Each repo's CI is triggered on PR open/update to `master/main` or `release/**`. It calls the reusable `ci.yml` from sonarmd/workflows and fills in its three job steps.

**Example (triggr_api):**
```yaml
name: CI
on:
  pull_request:
    branches: [master, 'release/**']
  merge_group:
    branches: [master, 'release/**']

jobs:
  ci:
    uses: sonarmd/workflows/.github/workflows/ci.yml@main
    with:
      setup: |
        sudo apt-get install -y graphicsmagick
        npm ci
      lint: |
        npm run lint
      test: |
        npm run test:ci
      build: |
        npm run build
      build-output: dist/
    secrets: inherit
```

---

### `cd.yml` (per-repo shim)

Triggered on push to `release/**` or `master/main` (i.e. after merge). Calls the universal CD.

**Example (triggr_api):**
```yaml
name: CD
on:
  push:
    branches: [master, 'release/**']

jobs:
  cd:
    uses: sonarmd/workflows/.github/workflows/cd.yml@main
    with:
      app: triggr_api
      repo-short: api
      slack-project: "Triggr API"
    secrets: inherit
```

That is the entire file. Ten lines. Done.

---

## deploy.json Contract

Lives in the root of each repo. Defines all deployable bundles. Ansible and Hubot read this file from the release artifact to know what to deploy and where.

**Schema:**
```json
{
  "app": "<app-name>",
  "bundles": [
    {
      "name": "<unique-bundle-name>",
      "path": "<path-within-artifact>",
      "target": "ec2 | s3 | lambda | eas",
      "hosts": ["<host-or-identifier>", "..."]
    }
  ]
}
```

**Field definitions:**

| Field | Description |
|---|---|
| `app` | App identifier. Matches Ansible role and Slack display name. |
| `name` | Unique bundle name within this repo. Used in Hubot commands and Ansible plays. |
| `path` | Path inside the release artifact tarball that contains this bundle's files. |
| `target` | Deploy target type. Determines which Ansible phase handles deployment. |
| `hosts` | One or more hosts/identifiers. For `ec2`: hostnames. For `s3`: bucket names. For `lambda`: function name or hostname tag. For `eas`: EAS project slug. If the list has multiple entries, the bundle is deployed to each one. |

**`${env}` interpolation:** The string `${env}` in any `hosts` entry is replaced by Ansible with the actual environment (`dev`, `stg`, `prd`) at deploy time.

**Examples:**

```json
// triggr_api
{
  "app": "triggr_api",
  "bundles": [
    {
      "name": "api",
      "path": "dist/",
      "target": "ec2",
      "hosts": [
        "api01-${env}.sonarmd.net",
        "api02-${env}.sonarmd.net",
        "jobs-${env}.sonarmd.net"
      ]
    }
  ]
}

// frontend (web — monorepo)
{
  "app": "frontend",
  "bundles": [
    {
      "name": "admin",
      "path": "admin/dist/",
      "target": "s3",
      "hosts": ["<admin-bucket-${env}>"]
    },
    {
      "name": "provider",
      "path": "provider/dist/",
      "target": "s3",
      "hosts": ["<provider-bucket-${env}>"]
    },
    {
      "name": "patient",
      "path": "patient/dist/",
      "target": "s3",
      "hosts": ["<patient-bucket-${env}>"]
    },
    {
      "name": "seat",
      "path": "seat/dist/",
      "target": "s3",
      "hosts": ["<seat-bucket-${env}>"]
    }
  ]
}

// frontend-patient-app (mobile)
{
  "app": "patient-mobile",
  "bundles": [
    {
      "name": "mobile",
      "path": ".",
      "target": "eas",
      "hosts": ["<eas-project-slug>"]
    }
  ]
}
```

---

## Deploy Flow — End to End

### Normal path (every repo except mobile)

```
Developer opens PR to release/** or master/main
  └── ci.yml fires (PR event)
        ├── ping-slack: "CI started — {app} #{PR}"  →  #ops
        ├── setup (repo fills in)
        ├── lint     (repo fills in)  →  lint artifact
        ├── test     (repo fills in)  →  JUnit XML artifact
        ├── build    (repo fills in)  →  build artifact
        ├── sbom-generator runs on build output
        ├── ci-sign signs all artifacts with ${{ github.sha }}
        ├── uploads ci-evidence artifact (build.tar.gz + sbom.json + .sig)
        └── ping-slack: "CI passed/failed — {app} #{PR}"  →  #ops

PR merged (rebase FF) → tip of branch IS the CI commit
  └── cd.yml shim fires (push to branch event)
        ├── ping-slack: "CD started — {app} {branch}"  →  #ops
        ├── resolve-env: branch → env, read version from package.json
        ├── check-ci-artifact: look for ci-evidence on ${{ github.sha }}
        │     ├── [found]     → continue to auto-tag
        │     └── [not found] → ping-slack: "No CI artifact — running CI first"
        │                       run full CI pipeline (setup/lint/test/build/sign/sbom)
        │                       if CI fails → ping-slack failure, abort
        ├── auto-tag: creates {env}-{repo-short}-{version}-b{run} tag
        ├── github-release:
        │     ├── uses ci-evidence from existing run or fallback run
        │     ├── downloads build.tar.gz → release.tar.gz
        │     └── creates GitHub Release at tag (prerelease if stg)
        ├── ping-slack per bundle:
        │     "@r2-d2 {app} {bundle} {env} {tag} {artifact_url}"  →  #ops
        └── ping-slack: "CD passed/failed — {app} {tag}"  →  #ops

Hubot sees "@r2-d2 triggr_api api prd prd-api-1.4.2-b188 https://..."
  └── invokes Ansible deploy.yml with:
        deploy_app, deploy_bundle, deploy_tag, deploy_env,
        deploy_target (from deploy.json), deploy_hosts (from deploy.json),
        artifact_url
  └── Ansible:
        ├── downloads release.tar.gz from GitHub Release
        ├── extracts bundle path
        └── deploys to each host per deploy_target (ec2/s3/lambda)
```

### Mobile path (frontend-patient-app)

```
CI is identical to above except:
  └── build step runs: eas build --local --platform all
        (sanity check only — validates the app compiles and exports)
        Output artifact attached to ci-evidence like any other build.

CD is identical to above.
  └── Slack ping lands in #ops as normal.

Hubot sees "@r2-d2 patient-mobile mobile stg stg-mobile-1.2.0-b44 https://..."
  └── invokes Ansible deploy.yml with deploy_target=eas
  └── Ansible EAS phase:
        ├── reads deploy.json from release artifact
        ├── calls eas-cli with the git tag:
        │     npx eas-cli build --profile {profile} --platform all \
        │                       --git-ref {tag} --non-interactive
        └── EAS handles the actual cloud build and store submission
```

---

## What Gets Removed From Each Repo

| File | Action |
|---|---|
| `auto-tag.yml` | Delete — handled by cd.yml |
| `draft-release.yml` | Delete — handled by cd.yml |
| `ping-slack.yml` | Delete — handled by cd.yml |
| `deploy.yml` (tag-triggered notify) | Delete — handled by cd.yml |
| `break-glass.yml` | Keep only in frontend-patient-app |

Only `ci.yml` (repo's stub implementation) and `cd.yml` (shim) remain.

---

## What Gets Removed From sonarmd/workflows

| File | Action |
|---|---|
| `.github/workflows/build-gate.yml` | Delete |
| `.github/workflows/deploy-api-ssm.yml` | Delete |
| `.github/workflows/deploy-eas-build.yml` | Delete |
| `.github/workflows/deploy-ecs.yml` | Delete |
| `.github/workflows/deploy-gate.yml` | Delete |
| `.github/workflows/deploy-s3-cloudfront.yml` | Delete |
| `.github/workflows/gate.yml` | Delete |
| `.github/workflows/metrics-collector.yml` | Delete |
| `.github/workflows/metrics-report.yml` | Delete |
| `.github/workflows/notify-slack.yml` | Delete — replaced by actions/ping-slack |
| `.github/workflows/static-analysis-gate.yml` | Delete |
| `.github/workflows/tag-release.yml` | Delete — replaced by actions/auto-tag |
| `.github/workflows/test-gate.yml` | Delete |
| `.github/workflows/dike-verify.yml` | Move → `.github/workflows/agora/dike-verify.yml` |
| `.github/workflows/dike-seal.yml` | Move → `.github/workflows/agora/dike-seal.yml` |

---

## Open Items

Before implementation begins, confirm the following with the team:

- [ ] **Frontend S3 bucket names** — replace `<admin-bucket-${env}>` etc. in frontend `deploy.json`
- [ ] **EAS project slug** — replace `<eas-project-slug>` in frontend-patient-app `deploy.json`
- [ ] **EAS CLI on Ansible deploy server** — confirm `npx eas-cli` is available or installed in the Ansible role
- [ ] **Rebase FF enforcement** — confirm branch protection rules enforce rebase-only merges on `master/main` and `release/**` for all repos (required for CD artifact lookup by commit SHA to be reliable)
- [ ] **GitHub token scope for cd.yml** — `GH_RELEASE_TOKEN` needs `contents:write` + `actions:read` to find workflow artifacts across runs
