# SonarMD Deploy Runbook

Implementation reference for the full CI/CD pipeline — from the moment a developer opens a PR to code running in production. Covers GitHub Actions, Hubot, Ansible, Makefile dispatch, and every handoff in between.

Read `CICD_FINALFINAL.md` for the architecture spec. Read this file for how it actually works, what every file does, and how to debug it.

---

## System Map

```
GitHub Actions (sonarmd/workflows)
  ├── ci.yml           Runs on PR. Builds, tests, signs, uploads ci-evidence artifact.
  ├── cd.yml           Runs on merge. Tags, releases, pings Hubot per bundle.
  └── actions/
        ├── ping-slack         Posts to #ops (or raw Hubot command via message: input)
        ├── auto-tag           Creates {env}-{repo-short}-{version}-b{run} tag
        ├── ci-sign            Downloads 1Password CLI, packs build output, uploads ci-evidence artifact
        ├── sbom-generator     Runs syft, generates CycloneDX SBOM
        └── github-release     Finds ci-evidence artifact, creates GitHub Release with release.tar.gz

Hubot (hubot-deploy-triggr)
  └── src/deploy.ts    Listens for @r2-d2 messages in #ops. Verifies sender. Dispatches make targets.

Ansible (triggr_misc/Ansible)
  ├── deploy.yml       Artifact downloader. Downloads + extracts to /tmp/deploy/{tag}/{bundle}/.
  ├── api_prd.yml      EC2 deploy (production). Runs base + triggr_api roles. Serial, any_errors_fatal.
  ├── api_stg.yml      EC2 deploy (staging). Same structure.
  ├── api_dev.yml      EC2 deploy (dev). Same structure.
  ├── fe_prd.yml       S3 deploy (production). Syncs bundle, sets cache headers, invalidates CloudFront.
  ├── fe_stg.yml       S3 deploy (staging). Identical logic, different bucket via deploy_hosts.
  ├── fe_dev.yml       S3 deploy (dev). Identical logic, different bucket via deploy_hosts.
  ├── eas_prd.yml      EAS build trigger (production). Clones, yarn install, eas-cli build.
  ├── eas_stg.yml      EAS build trigger (staging). Profile: preview.
  ├── eas_dev.yml      EAS build trigger (dev). Profile: development.
  ├── Makefile         Dispatch layer. Translates make targets + make vars into ansible-playbook calls.
  └── roles/
        └── triggr_api/
              └── tasks/
                    ├── install.yml   Downloads artifact via GitHub App token, extracts, deploys.
                    └── lambda.yml    Zips + deploys Lambda bundles found under dist/lambdas/.
```

---

## Repository Inventory

| Repo | CI | CD | deploy.json |
|---|---|---|---|
| `sonarmd/triggr_api` | `.github/workflows/ci.yml` | `.github/workflows/cd.yml` | `deploy.json` |
| `sonarmd/frontend` | `.github/workflows/ci.yml` | `.github/workflows/cd.yml` | `deploy.json` |
| `sonarmd/frontend-patient-app` | `.github/workflows/ci.yml` | `.github/workflows/cd.yml` | `deploy.json` |
| `sonarmd/workflows` | Source of truth for all reusable actions + workflows | — | — |
| `sonarmd/hubot-deploy-triggr` | — | — | deploy logic |
| `sonarmd/triggr_misc` | — | — | Ansible playbooks + Makefile |

---

## deploy.json Contract

Each repo's `deploy.json` defines what gets deployed and where. Hubot reads this (via cd.yml, which checks it out) to know how many Hubot messages to send. Ansible reads it via vars passed on the make command.

```json
{
  "app": "<app-identifier>",
  "bundles": [
    {
      "name": "<bundle-name>",
      "path": "<path-in-artifact>",
      "target": "ec2 | s3 | lambda | eas",
      "hosts": "<see below>"
    }
  ]
}
```

### hosts field shapes

**EC2 — array with `${env}` interpolation:**
```json
"hosts": ["api-${env}.sonarmd.net", "jobs-${env}.sonarmd.net"]
```
cd.yml substitutes `${env}` and joins with commas. Hubot receives `api-prd.sonarmd.net,jobs-prd.sonarmd.net`.

**S3 — env-keyed object (prd has no prefix, so array won't work):**
```json
"hosts": {
  "dev": "care.dev.sonarmd.com",
  "stg": "care.stg.sonarmd.com",
  "prd": "care.sonarmd.com"
}
```
cd.yml picks `hosts[env]`. Hubot receives `care.sonarmd.com`.

**EAS — null or absent:**
```json
"hosts": null
```
cd.yml falls back to `"eas"`. Hubot receives `eas`. Ansible ignores it (no S3 bucket needed).

### Current deploy.json files

**triggr_api/deploy.json:**
```json
{
  "app": "triggr_api",
  "bundles": [
    {
      "name": "api",
      "path": "dist",
      "target": "ec2",
      "artifact_paths": ["dist/", "node_modules/", "package.json"],
      "hosts": ["api-${env}.sonarmd.net", "jobs-${env}.sonarmd.net"]
    }
  ]
}
```

**frontend/deploy.json:**
```json
{
  "app": "frontend",
  "bundles": [
    { "name": "admin",   "path": "admin/build/",   "target": "s3", "hosts": { "dev": "admin.dev.sonarmd.com",  "stg": "admin.stg.sonarmd.com",  "prd": "admin.sonarmd.com"  } },
    { "name": "care",    "path": "provider/build/", "target": "s3", "hosts": { "dev": "care.dev.sonarmd.com",   "stg": "care.stg.sonarmd.com",   "prd": "care.sonarmd.com"   } },
    { "name": "patient", "path": "patient/build/",  "target": "s3", "hosts": { "dev": "my.dev.sonarmd.com",    "stg": "my.stg.sonarmd.com",     "prd": "my.sonarmd.com"     } },
    { "name": "seat",    "path": "seat/build/",     "target": "s3", "hosts": { "dev": "seat.dev.sonarmd.com",  "stg": "seat.stg.sonarmd.com",   "prd": "seat.sonarmd.com"   } }
  ]
}
```

Note: `care` bundle maps to `provider/build/` because the source directory is `provider/` but the domain and bundle name is `care`.

**frontend-patient-app/deploy.json:**
```json
{
  "app": "patient-mobile",
  "bundles": [
    {
      "name": "mobile",
      "path": ".",
      "target": "eas",
      "hosts": null
    }
  ]
}
```

---

## CI Pipeline (GitHub Actions)

**Trigger:** `pull_request` to `master` or `release/**`, plus `merge_group`.

**Flow:**

```
1. ping-slack action
   → Posts "CI started: {app} PR#{number}" to #ops via SLACK_WEBHOOK_URL

2. [repo-specific] setup, lint, test, build jobs
   → Each repo fills in these steps. CI stub calls them via workflow_call.
   → triggr_api: apt install graphicsmagick, yarn install, yarn lint, yarn test:ci, yarn build
   → frontend: detect changed apps, build each changed sub-app
   → frontend-patient-app: yarn install, expo export (sanity check)

3. sbom-generator action
   → Runs syft v1.18.1 on build output
   → Produces sbom.json (CycloneDX format)
   → Falls back to minimal JSON on failure (never blocks CI)

4. ci-sign action
   → Installs 1Password CLI (op) via OP_SERVICE_ACCOUNT_TOKEN
   → Packs build output as build.tar.gz
   → Creates sha256 manifest.json (file → hash for every file in build output)
   → Uploads ci-evidence artifact: build.tar.gz + manifest.json + sbom.json + test report
   → Artifact retention: 30 days

5. ping-slack action
   → Posts "CI passed/failed: {app} PR#{number}" to #ops
```

**ci-evidence artifact contents:**
```
ci-evidence/
  build.tar.gz       Build output (what gets deployed)
  manifest.json      SHA256 hashes of every file
  sbom.json          CycloneDX SBOM
  test-report.xml    JUnit XML (if test step produced one)
```

---

## CD Pipeline (GitHub Actions)

**Trigger:** `push` to `master` or `release/**` (fires after merge).

**Branch → environment mapping:**
```
master / main  →  prd
release/**     →  stg
anything else  →  dev
```

**Flow:**

```
1. setup job
   ├── ping-slack: "CD started: {app} on {branch}"
   ├── Checkout repo (to read package.json + deploy.json)
   ├── Parse environment from branch name
   ├── Read version: node -p "require('./package.json').version"
   └── Find ci-evidence artifact:
         gh api repos/{owner}/{repo}/actions/runs?head_sha={sha}&status=completed
         → iterate successful runs, look for ci-evidence artifact (not expired)
         → output: ci_artifact_exists (true/false), ci_artifact_run_id

2. ci-fallback job  [ONLY if ci_artifact_exists == false]
   ├── ping-slack: ":warning: No CI artifact found for {sha} — running fallback build"
   ├── Fails hard if no build-command provided
   └── Runs full CI inline: checkout → pre-install → build → sbom → ci-sign → upload

3. tag job  [after setup + ci-fallback, whichever ran]
   └── auto-tag action:
         tag = {env}-{repo-short}-{version}-b{run_number}
         e.g. prd-api-1.4.2-b188, stg-fe-2.1.0-b77

4. release job  [after tag]
   └── github-release action:
         ├── Downloads ci-evidence artifact from the run identified in setup (or fallback run)
         ├── Extracts build.tar.gz → renames to release.tar.gz
         ├── Creates GitHub Release at the new tag
         │     prerelease=true  if env == stg
         │     latest=true      if env == prd
         └── Outputs:
               artifact-url = https://api.github.com/repos/sonarmd/{repo}/releases/tags/{tag}
               release-url  = https://github.com/sonarmd/{repo}/releases/tag/{tag}

5. notify job  [after setup + tag + release]
   ├── Checkout repo (to read deploy.json)
   ├── For each bundle in deploy.json:
   │     Resolve hosts:
   │       hosts is object → pick hosts[env]
   │       hosts is array  → substitute ${env}, join with comma
   │       hosts is null   → "eas"
   │     Post to Slack #ops:
   │       @r2-d2 {app} {bundle_name} {env} {tag} {hosts} {artifact_url}
   └── ping-slack: "CD passed/failed: {app} {tag}"
```

**Key constraint:** Rebase FF-only merges are required. After a rebase-merge, the tip of the target branch IS the commit that ran CI. This is what makes `github.sha` in CD reliable for artifact lookup.

---

## Hubot (deploy.ts)

**File:** `hubot-deploy-triggr/src/deploy.ts`

**Listens in:** `#ops`, `#deployments`, `#ops-dev`

**Message pattern matched:**
```
@r2-d2 {app} {bundle} {env} {tag} {hosts_csv} {artifact_url}
```
Where `artifact_url` must match `https://api.github.com/repos/sonarmd/...`

**Authorization checks (in order):**
1. Channel must be in `ALLOWED_CHANNELS` — else ignore silently
2. `msg.message.user.id` must equal `AGORA_BOT_USER_ID` env var — else ignore silently
3. `artifact_url` must start with `https://api.github.com/repos/sonarmd/` — else reply with error
4. `env` must be `dev`, `stg`, or `prd` — else reply with error
5. `app` must be in `APP_TARGET_MAP` — else reply with error

**App → Makefile target mapping:**
```
triggr_api     →  api_{env}   →  make api_prd / api_stg / api_dev
frontend       →  fe_{env}    →  make fe_prd  / fe_stg  / fe_dev
patient-mobile →  eas_{env}   →  make eas_prd / eas_stg / eas_dev
```

**On receipt of valid message:**
```
1. Post to #ops: ":rocket: Deploying {app}/{bundle} ({tag}) → {env} | make {target} | Hosts: {hosts}"
2. Build make command:
     make --no-print-directory -C {ANSIBLE_DIR} {target}
       deploy_tag={tag}
       artifact_url={artifact_url}
       deploy_bundle={bundle}
       deploy_hosts={hosts_csv}
       deploy_env={env}
3. exec() with 20-minute timeout, 10MB stdout buffer
4. On success: post PLAY RECAP to #ops
5. On failure: post last 30 lines + PLAY RECAP to #ops
```

**Required env vars on deploy server:**
```
AGORA_BOT_USER_ID   Slack user ID of the Agora bot (only source allowed to trigger deploys)
ANSIBLE_DIR         Path to Ansible dir (default: /root/triggr_misc/Ansible)
GITHUB_TOKEN        GitHub token for Ansible artifact downloads
EXPO_TOKEN          Expo token for EAS builds
```

---

## Makefile Dispatch

**File:** `triggr_misc/Ansible/Makefile`

**How vars flow through:**
The Makefile uses `ifdef` blocks to conditionally append `-e {var}={val}` to the `ANSIBLE` variable. Any var passed as `make target var=value` gets added to every `ansible-playbook` call in that target.

```makefile
# These vars are appended to ANSIBLE if provided:
deploy_tag      -e deploy_tag=$(deploy_tag)
artifact_url    -e artifact_url=$(artifact_url)
deploy_bundle   -e deploy_bundle=$(deploy_bundle)
deploy_hosts    -e deploy_hosts=$(deploy_hosts)
deploy_env      -e deploy_env=$(deploy_env)
host            -e target=$(host)
tags            --tags $(tags)
verbose         -vvvv
```

**Deploy targets:**

| Target | Requires | Calls |
|---|---|---|
| `api_dev` | `deploy_tag` | `api_dev.yml` |
| `api_stg` | `deploy_tag` | `api_stg.yml`, `deploy_etl_stg.yml` |
| `api_prd` | `deploy_tag` | `api_prd.yml`, `deploy_etl_prd.yml` |
| `fe_dev` | `deploy_tag`, `deploy_bundle`, `deploy_hosts` | `deploy.yml`, `fe_dev.yml` |
| `fe_stg` | `deploy_tag`, `deploy_bundle`, `deploy_hosts` | `deploy.yml`, `fe_stg.yml` |
| `fe_prd` | `deploy_tag`, `deploy_bundle`, `deploy_hosts` | `deploy.yml`, `fe_prd.yml` |
| `eas_dev` | `deploy_tag` | `eas_dev.yml` |
| `eas_stg` | `deploy_tag` | `eas_stg.yml` |
| `eas_prd` | `deploy_tag` | `eas_prd.yml` |

---

## Ansible Playbooks

### deploy.yml — Artifact Downloader

Used by `fe_*` targets. Downloads the GitHub Release artifact for a specific bundle to `/tmp/deploy/{deploy_tag}/{deploy_bundle}/`.

**What it does:**
1. Validates: `deploy_tag`, `deploy_bundle`, `artifact_url`, `GITHUB_TOKEN`
2. Creates `/tmp/deploy/{deploy_tag}/{deploy_bundle}/`
3. GET `{artifact_url}` → GitHub release metadata JSON
4. Extracts `release.tar.gz` asset URL from metadata
5. Downloads `release.tar.gz`
6. Extracts in place
7. Removes tarball

**Not used by:**
- `api_*` — triggr_api role downloads its own artifact inside `install.yml` using a GitHub App token
- `eas_*` — EAS playbooks clone the source repo instead of downloading a prebuilt artifact

---

### api_prd.yml / api_stg.yml / api_dev.yml — EC2 Deploy

Targets EC2 instances via Ansible dynamic inventory (tag-based groups).

**Inventory groups:**
```
tag_InstanceType_APIProduction  →  api_prd.yml (default)
tag_InstanceType_APIStaging     →  api_stg.yml (default)
tag_InstanceType_APIDevelopment →  api_dev.yml (default)
```
The `host` make var overrides the target group: `make api_prd host=tag_InstanceType_SomeOtherGroup`.

**Flow per host (serial: 1, any_errors_fatal: true):**
```
1. slack role: "Deploying triggr_api:{tag} to {hostname} in {env}"
2. base role:  System-level setup (packages, configs)
3. triggr_api role:
   ├── install.yml:
   │     ├── Install system packages (graphicsmagick, libkrb5-dev, etc.)
   │     ├── Generate GitHub App installation token (JWT via PyJWT)
   │     ├── Download artifact from artifact_url using token
   │     ├── Extract to /tmp/api/
   │     ├── Deploy configuration (configuration.j2 template)
   │     ├── Deploy SSL certs + keys
   │     └── Move /tmp/api/* → api_install_path
   ├── jobs.yml:   (if ec2_tag_APIRole == "Jobs") — cron job setup
   ├── server.yml: (if ec2_tag_APIRole == "Server" or "FTP") — PM2/process management
   └── lambda.yml: (for each dir under dist/lambdas/, if present)
         ├── Zip bundle with community.general.archive
         └── Deploy with amazon.aws.lambda
4. slack role: "Deploy of triggr_api:{tag} to {hostname} in {env} complete"
```

**Note on Lambda deploys (api_prd):**
Lambda functions are deployed as part of the api role, not as a separate make target. If `dist/lambdas/` exists in the artifact, `install.yml` finds subdirectories and loops over them. Each subdirectory name becomes the function name suffix: `{dirname}-{env}`. The function must have a `tags.Hostname` tag matching the hostname for tag-based discovery.

Lambdas are currently **not in production deploy.json** (the escalation/ml/signal bundles were removed). Lambda deploy via this path is staged but not active.

---

### fe_prd.yml / fe_stg.yml / fe_dev.yml — S3 Deploy

Artifact must already be at `/tmp/deploy/{deploy_tag}/{deploy_bundle}/` (put there by `deploy.yml`).

**Flow:**
```
1. Validate: deploy_bundle, deploy_hosts, deploy_tag
2. amazon.aws.s3_sync:
     bucket = deploy_hosts (resolved S3 bucket name)
     file_root = /tmp/deploy/{tag}/{bundle}/
     delete = true
     cache_control = "public, max-age=31536000, immutable"
     exclude = index.html, service-worker.js, asset-manifest.json
3. amazon.aws.s3_object (index.html):
     Cache-Control: no-cache, no-store, must-revalidate
     Content-Type: text/html
4. amazon.aws.s3_object (service-worker.js, if exists)
5. amazon.aws.s3_object (asset-manifest.json, if exists)
6. amazon.aws.cloudfront_distribution_info:
     alias = deploy_hosts
     → must return exactly 1 distribution (fails otherwise)
7. amazon.aws.cloudfront_distribution:
     distribution_id = cf_info.distributions[0].id
     invalidation.paths = ["/*"]
8. Cleanup /tmp/deploy/{deploy_tag}/
```

**Why two separate S3 operations instead of one sync:**
CRA apps and Vite apps use content-addressed filenames (e.g. `main.abc123.js`) for everything except `index.html`, `service-worker.js`, and `asset-manifest.json`. The content-addressed files can be cached forever (immutable). The entry points must never be cached so browsers always load the latest version.

---

### eas_prd.yml / eas_stg.yml / eas_dev.yml — EAS Cloud Build

**EAS profile mapping:**
```
prd  →  production
stg  →  preview
dev  →  development
```

**Flow:**
```
1. Validate: deploy_tag, artifact_url, GITHUB_TOKEN, EXPO_TOKEN
2. Derive repo name: regex on artifact_url
     https://api.github.com/repos/sonarmd/{repo-name}/releases/tags/...
3. git clone --depth 1 at deploy_tag:
     https://x-access-token:{GITHUB_TOKEN}@github.com/sonarmd/{repo_name}.git
4. yarn install --frozen-lockfile --non-interactive
5. npx eas-cli build \
       --platform all \
       --profile {eas_profile} \
       --non-interactive \
       --no-wait           ← submits and returns immediately; EAS handles async build
   (EXPO_TOKEN injected into environment)
6. Log expo.dev URLs from stdout
7. Cleanup /tmp/deploy/{deploy_tag}/eas-src/
```

**`--no-wait` is intentional.** EAS cloud builds take 10–40 minutes. The playbook submits the build and returns. Monitor progress at expo.dev/accounts/sonarmd.

---

## End-to-End Flow: Feature Branch → Production

### 1. Development

```
Developer creates feature branch from master.
Writes code, commits.
Opens PR targeting master (for prd) or release/x.y (for stg).
```

---

### 2. CI Runs (PR)

```
GitHub Actions fires ci.yml.

For triggr_api:
  - apt install graphicsmagick
  - yarn install
  - yarn lint  →  linting output
  - yarn test:ci (with MongoDB service container)  →  JUnit XML
  - yarn build  →  dist/
  - sbom-generator: syft on dist/ → sbom.json
  - ci-sign: pack dist/ → build.tar.gz, create manifest.json, upload ci-evidence artifact
  → #ops: "CI passed: triggr_api PR#123"

For frontend:
  - detect-changed-apps: which of admin/care/patient/seat changed
  - Build only changed apps: yarn workspace {name} build  →  {name}/build/
  - sbom-generator, ci-sign on each build
  → #ops: "CI passed: frontend PR#456"

For frontend-patient-app:
  - yarn install
  - expo export --platform all (sanity check)
  - sbom-generator, ci-sign
  → #ops: "CI passed: patient-mobile PR#789"
```

---

### 3. PR Review + Merge

```
Reviewer approves PR.
Branch is rebased onto master (rebase FF enforced by branch protection).
After merge, the tip of master IS the commit that ran CI.
  → This is the invariant that makes CD artifact lookup work.
```

---

### 4. CD Runs (Post-Merge)

```
Push to master fires cd.yml.

setup job:
  - Parse env: master → prd
  - Read version from package.json: e.g. 1.4.2
  - Look for ci-evidence on github.sha:
      gh api repos/sonarmd/triggr_api/actions/runs?head_sha={sha}&status=completed
      → finds the CI run from step 2
      → ci_artifact_exists=true, ci_artifact_run_id=123456

tag job:
  - auto-tag: prd-api-1.4.2-b188

release job:
  - Download ci-evidence from run 123456
  - Extract build.tar.gz → /tmp/release.tar.gz
  - gh release create prd-api-1.4.2-b188 /tmp/release.tar.gz --latest
  - artifact_url = https://api.github.com/repos/sonarmd/triggr_api/releases/tags/prd-api-1.4.2-b188

notify job (for triggr_api — 1 bundle):
  - Read deploy.json: bundle "api", hosts=["api-${env}.sonarmd.net","jobs-${env}.sonarmd.net"]
  - Substitute ${env} → prd: api-prd.sonarmd.net,jobs-prd.sonarmd.net
  - Post to #ops:
      @r2-d2 triggr_api api prd prd-api-1.4.2-b188 api-prd.sonarmd.net,jobs-prd.sonarmd.net https://api.github.com/repos/sonarmd/triggr_api/releases/tags/prd-api-1.4.2-b188

notify job (for frontend — 4 bundles):
  - Posts 4 separate messages to #ops, one per bundle:
      @r2-d2 frontend admin   prd prd-fe-2.1.0-b77 admin.sonarmd.com   https://...
      @r2-d2 frontend care    prd prd-fe-2.1.0-b77 care.sonarmd.com    https://...
      @r2-d2 frontend patient prd prd-fe-2.1.0-b77 my.sonarmd.com      https://...
      @r2-d2 frontend seat    prd prd-fe-2.1.0-b77 seat.sonarmd.com    https://...
  (All 4 use the same tag + artifact_url — single release, multiple bundles)
```

---

### 5. Hubot Receives Messages (#ops)

```
For each @r2-d2 message:

1. Channel check: #ops ✓
2. Sender check: msg.message.user.id == AGORA_BOT_USER_ID ✓
3. Namespace check: artifact_url.startsWith("https://api.github.com/repos/sonarmd/") ✓
4. App lookup: triggr_api → target prefix "api"
5. make target: api_prd

Post to #ops: ":rocket: Deploying triggr_api/api (prd-api-1.4.2-b188) → prd | make api_prd | Hosts: api-prd.sonarmd.net,jobs-prd.sonarmd.net"

Execute:
  make --no-print-directory -C /root/triggr_misc/Ansible api_prd \
    deploy_tag=prd-api-1.4.2-b188 \
    artifact_url=https://api.github.com/repos/sonarmd/triggr_api/releases/tags/prd-api-1.4.2-b188 \
    deploy_bundle=api \
    deploy_hosts=api-prd.sonarmd.net,jobs-prd.sonarmd.net \
    deploy_env=prd
```

---

### 6. Ansible Runs

#### For triggr_api (EC2):

```
Makefile api_prd calls:
  ansible-playbook -i inventories/aws_ec2.yml \
    --vault-password-file .get-vault-password \
    --private-key ~/.ssh/AnsibleRoot.pem \
    -e deploy_tag=prd-api-1.4.2-b188 \
    -e artifact_url=https://... \
    -e deploy_bundle=api \
    -e deploy_hosts=api-prd.sonarmd.net,jobs-prd.sonarmd.net \
    -e deploy_env=prd \
    api_prd.yml

api_prd.yml targets: tag_InstanceType_APIProduction
  → resolves to all EC2 instances tagged InstanceType=APIProduction
  → runs serial: 1 (one host at a time, rolling deploy)

For each host:
  slack role → slack: "Deploying triggr_api:prd-api-1.4.2-b188 to api-prd-01 in production"
  base role  → system packages, config, monitoring
  triggr_api role → install.yml:
    1. Generate GitHub App JWT → exchange for installation token
    2. Download artifact from artifact_url
    3. Extract to /tmp/api/
    4. Write configuration.json from vault template
    5. Deploy SSL certs from encrypted role files
    6. mv /tmp/api/* → /var/www/triggr_api/
    7. If dist/lambdas/ exists: deploy each Lambda bundle
  triggr_api role → jobs.yml or server.yml based on ec2_tag_APIRole tag
  slack role → "Deploy of triggr_api:prd-api-1.4.2-b188 to api-prd-01 in production complete"

Makefile also calls deploy_etl_prd.yml for ETL hosts.

Hubot receives stdout, extracts PLAY RECAP, posts to #ops:
  ":white_check_mark: Deploy SUCCESS: triggr_api/api (prd-api-1.4.2-b188) → prd
  PLAY RECAP
  api-prd-01 : ok=14 changed=6 unreachable=0 failed=0
  api-prd-02 : ok=14 changed=6 unreachable=0 failed=0
  jobs-prd   : ok=14 changed=6 unreachable=0 failed=0"
```

#### For frontend (S3), one bundle as example:

```
Makefile fe_prd calls (for "care" bundle):
  1. ansible-playbook ... deploy.yml
     → Downloads release.tar.gz for "care" bundle from artifact_url
     → Extracts to /tmp/deploy/prd-fe-2.1.0-b77/care/

  2. ansible-playbook ... fe_prd.yml
     → s3_sync: /tmp/deploy/.../care/ → care.sonarmd.com
         Cache-Control: public, max-age=31536000, immutable
         Excludes: index.html, service-worker.js, asset-manifest.json
     → s3_object: index.html → Cache-Control: no-cache, no-store, must-revalidate
     → s3_object: asset-manifest.json → same
     → cloudfront_distribution_info: alias=care.sonarmd.com → distribution_id
     → cloudfront_distribution: invalidate [/*]
     → file: /tmp/deploy/prd-fe-2.1.0-b77/ absent

Hubot posts to #ops: ":white_check_mark: Deploy SUCCESS: frontend/care (prd-fe-2.1.0-b77) → prd"
```

Hubot processes all 4 frontend bundle messages independently. They may overlap in execution.

#### For frontend-patient-app (EAS):

```
Makefile eas_prd calls:
  ansible-playbook ... eas_prd.yml
    1. Regex artifact_url → repo_name = "frontend-patient-app"
    2. git clone --depth 1 prd-mobile-1.2.0-b44
         → https://x-access-token:{token}@github.com/sonarmd/frontend-patient-app.git
    3. yarn install --frozen-lockfile --non-interactive
    4. npx eas-cli build --platform all --profile production --non-interactive --no-wait
       (EXPO_TOKEN in env)
    5. Log expo.dev URLs from stdout
    6. Cleanup /tmp/deploy/prd-mobile-1.2.0-b44/eas-src/

Hubot posts to #ops: ":white_check_mark: Deploy SUCCESS: patient-mobile/mobile (prd-mobile-1.2.0-b44) → prd"
```

---

## Environment Mappings Summary

| GitHub branch | env var | Tag prefix | EC2 group | S3 bucket suffix | EAS profile |
|---|---|---|---|---|---|
| `master` / `main` | `prd` | `prd-` | `tag_InstanceType_APIProduction` | `sonarmd.com` | `production` |
| `release/**` | `stg` | `stg-` | `tag_InstanceType_APIStaging` | `.stg.sonarmd.com` | `preview` |
| other | `dev` | `dev-` | `tag_InstanceType_APIDevelopment` | `.dev.sonarmd.com` | `development` |

---

## Key Design Decisions

**1. CD never rebuilds. It uses the CI artifact.**

The CI run on a commit produces `ci-evidence`. If CI passed, that artifact is the deployable artifact. CD looks it up by commit SHA. Rebase FF merges ensure the merged commit IS the CI commit. This removes a whole class of "it passed in CI but something changed before deploy" bugs.

**2. deploy.yml is a downloader, not an orchestrator.**

`deploy.yml` only validates and downloads. It knows nothing about EC2, S3, CloudFront, or EAS. Routing to the correct playbook is the Makefile's job. Deployment logic lives in env-specific playbooks (`api_prd.yml`, `fe_prd.yml`, etc.) or roles. This keeps each playbook focused and independently readable.

**3. triggr_api role downloads its own artifact.**

The EC2 deploy path is fundamentally different from S3/EAS: it runs on remote hosts, not localhost. `install.yml` generates a GitHub App token (short-lived, not stored) and downloads the artifact directly on the target EC2 instance. This avoids a controller→EC2 file transfer of potentially large artifacts.

**4. Hubot only accepts messages from the Agora bot.**

The Agora bot posts the `@r2-d2` message to #ops after CD creates the release. Only the bot's user ID is accepted. Human-typed deploy commands are silently ignored. This creates a clean audit trail: every deploy is traceable to a specific CD run and a specific commit.

**5. Frontend uses env-keyed host objects, not `${env}` arrays.**

Production domains don't have a `prd.` prefix (e.g. `care.sonarmd.com` not `care.prd.sonarmd.com`). An array with `${env}` substitution can't express this. An object `{dev: ..., stg: ..., prd: ...}` handles it cleanly.

**6. EAS uses `--no-wait`.**

EAS cloud builds compile React Native apps for iOS and Android. They take 10–40 minutes. Ansible does not wait. The playbook returns immediately after submission. Status is checked at expo.dev. If a build fails, the Expo team email/webhook (configured in the EAS project) handles alerting.

---

## Failure Modes

| Where | What happens | Hubot message |
|---|---|---|
| CI fails on PR | CD cannot run (no ci-evidence artifact on that SHA). CD fallback kicks in or CD aborts. | `#ops: ":warning: No CI artifact found"` |
| ci-fallback fails | CD aborts. No tag, no release, no deploy. | `#ops: "CD failed: {app} {branch}"` |
| Hubot can't reach Ansible dir | `exec()` fails immediately. | `#ops: ":x: Deploy FAILED — last 30 lines"` |
| Ansible playbook fails | Non-zero exit. Hubot captures stdout tail + PLAY RECAP. | `#ops: ":x: Deploy FAILED — {recap}"` |
| S3 bucket not found | `s3_sync` fails. fe_prd.yml exits. Cleanup does not run. | Ansible failure surfaces in PLAY RECAP |
| CloudFront distribution not found or 2+ found | `fail` task triggers explicitly. | `"Found N CloudFront distributions..."` |
| EAS CLI exits non-zero | Ansible `command` module marks task failed. Playbook exits. | Ansible failure |
| EC2 host unreachable | `any_errors_fatal: true` kills the play. No further hosts are touched. | `"UNREACHABLE"` in PLAY RECAP |

---

## Configuration Checklist

Things that must be set up before the pipeline is live:

**GitHub (branch protection, all repos):**
- [ ] Require rebase merges only (no merge commits, no squash) on `master` and `release/**`
- [ ] Require CI to pass before merge
- [ ] `GH_RELEASE_TOKEN` secret: needs `contents:write` + `actions:read`
- [ ] `OP_SERVICE_ACCOUNT_TOKEN_AGORA` secret: 1Password service account for ci-sign
- [ ] `SLACK_WEBHOOK_URL` secret: incoming webhook for `#ops`

**Deploy server (environment variables):**
- [ ] `AGORA_BOT_USER_ID` — Slack user ID of the Agora CD bot
- [ ] `GITHUB_TOKEN` — GitHub token or App token for Ansible artifact downloads
- [ ] `EXPO_TOKEN` — Expo access token for EAS builds
- [ ] `ANSIBLE_DIR` — `/root/triggr_misc/Ansible` (or override)

**Ansible (deploy server):**
- [ ] `/opt/ansible-env/bin/ansible-playbook` exists (or `ANSIBLE_PLAYBOOK` env var)
- [ ] `~/.ssh/AnsibleRoot.pem` — SSH key for EC2 access
- [ ] `~/triggr-vault-password.txt` or 1Password fallback configured for `.get-vault-password`
- [ ] AWS credentials available to Ansible (for S3/CloudFront/Lambda modules)
- [ ] `npx eas-cli` available on deploy server (for EAS targets)

**AWS:**
- [ ] S3 buckets exist for all frontend bundles (all envs)
- [ ] CloudFront distributions configured with the bucket hostname as alias (for CF lookup)
- [ ] EC2 instances tagged with `InstanceType` matching the group names in playbooks
