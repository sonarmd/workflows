# sonarmd/workflows

CI enforcement for SonarMD. Two pieces:

1. **`ci-sign`** - composite action. Add as the last step in your CI. Collects test evidence, generates an SBOM, and signs everything with Sigstore.
2. **`gate.yml`** - required workflow (org-level ruleset). Runs in the merge queue after all PR checks pass. Independently verifies the evidence. No evidence = no merge.

You own your CI. Install whatever you want, run whatever you want. The only requirements: produce JUnit XML test results, and call `ci-sign` at the end.

## How It Works

```
Your CI workflow:
  checkout -> setup -> deps -> lint -> test (JUnit XML) -> build -> ci-sign
                                                                      |
                                                            collects evidence:
                                                            - JUnit XML (test proof)
                                                            - CycloneDX SBOM
                                                            - build digest
                                                            signs with Sigstore
                                                                      |
merge queue (automatic):                                              v
  gate.yml -> verifies Sigstore attestation
           -> independently counts JUnit XML test cases
           -> checks SBOM exists
           -> verifies build digest + commit SHA
           -> PASS or FAIL (shown on dashboard)
```

If any step before `ci-sign` fails, GitHub Actions stops. `ci-sign` never runs. No attestation. Gate fails. PR blocked.

## Quick Start

Add this to `.github/workflows/ci.yml` in your repo:

```yaml
name: CI

on:
  push:
    branches: ['**']
  pull_request:
    branches: [master, staging, 'release/**']

permissions:
  contents: read
  id-token: write
  attestations: write

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # === Your setup - install whatever you need ===
      - uses: actions/setup-node@v4
        with:
          node-version: '18'
      - run: yarn install --frozen-lockfile

      # === Your checks - run whatever you run ===
      - run: yarn lint
      - run: yarn test --reporters=jest-junit
      - run: yarn build

      # === ci-sign - MUST be last ===
      - uses: sonarmd/workflows/actions/ci-sign@main
        with:
          test_report_path: junit.xml
```

That's it. The gate runs automatically in the merge queue.

## Working Examples

### triggr_api

Node 18, MongoDB, graphicsmagick. The project sets up its own service container and system deps.

```yaml
name: CI

on:
  push:
    branches: ['**']
  pull_request:
    branches: [master, staging, 'release/**']

permissions:
  contents: read
  id-token: write
  attestations: write

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  ci:
    runs-on: ubuntu-latest
    timeout-minutes: 12
    services:
      mongo:
        image: mongo:8.0
        ports:
          - 27017:27017
        options: >-
          --health-cmd "mongosh --eval 'db.adminCommand({ping:1})'"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '18'
      - run: sudo apt-get update -qq && sudo apt-get install -y graphicsmagick
      - run: yarn install --frozen-lockfile
      - run: yarn lint
      - run: yarn build
      - run: yarn test --reporters=jest-junit
        env:
          LOG_LEVEL: none
          TZ: utc
      - uses: sonarmd/workflows/actions/ci-sign@main
        with:
          test_report_path: junit.xml
          build_output_dir: dist
```

### frontend

React monorepo. Node 18 with `--openssl-legacy-provider` for legacy react-scripts. Shared library must build first.

```yaml
name: CI

on:
  push:
    branches: ['**']
  pull_request:
    branches: [master, staging, 'release/**']

permissions:
  contents: read
  id-token: write
  attestations: write

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

env:
  NODE_OPTIONS: --openssl-legacy-provider

jobs:
  ci:
    runs-on: ubuntu-latest
    timeout-minutes: 12
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '18'
      - run: yarn install --frozen-lockfile
      - run: yarn build-shared
      - run: yarn lint
      - run: yarn just-test --reporters=jest-junit
      - uses: sonarmd/workflows/actions/ci-sign@main
        with:
          test_report_path: junit.xml
```

### frontend-patient-app

React Native / Expo. Node 22. No build step - production builds go through EAS.

```yaml
name: CI

on:
  push:
    branches: ['**']
  pull_request:
    branches: [master, staging, 'release/**']

permissions:
  contents: read
  id-token: write
  attestations: write

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  ci:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
      - run: yarn install --frozen-lockfile
      - run: yarn lint
      - run: npx tsc --noEmit
      - run: yarn test --ci --reporters=jest-junit
      - uses: sonarmd/workflows/actions/ci-sign@main
        with:
          test_report_path: junit.xml
```

## Structure

```
actions/
  ci-sign/action.yml       Collects evidence, signs with Sigstore

.github/workflows/
  gate.yml                 Required workflow - merge queue, verifies everything
  deploy.yml               Reusable deploy - verifies attestation, pings Slack

per-repo/                  Ready-to-copy CI workflows for each project
  triggr_api/
  frontend/
  frontend-patient-app/
  triggr_misc/
```

## ci-sign

**What it does**: Collects CI evidence (test results, SBOM, build hashes), writes a manifest, and signs it with GitHub's native Sigstore attestation (`actions/attest-build-provenance`).

**Inputs**:

| Input | Default | Required | Description |
|-------|---------|----------|-------------|
| `test_report_path` | `junit.xml` | No | Path to JUnit XML test report. Must contain real test cases. |
| `build_output_dir` | _(empty)_ | No | Directory with build output. Every file gets SHA256 hashed. |

**What it collects**:

| Evidence | Source | Gate verifies |
|----------|--------|---------------|
| Test results | JUnit XML | Independently counts `<testcase>` elements |
| SBOM | CycloneDX (auto-detected) | Checks existence |
| Build digest | SHA256 of all build files | Matches manifest |
| Commit SHA | `github.sha` | Must match gate's commit |
| Sigstore attestation | `attest-build-provenance` | Cryptographic proof |

**When to call it**: As the last step in your CI job. If you have multiple jobs, put it at the end of the one that runs last.

**JUnit XML requirement**: Your test runner must produce JUnit XML. Every language has a reporter:

| Runner | Flag |
|--------|------|
| Jest | `--reporters=jest-junit` |
| Mocha | `--reporter mocha-junit-reporter` |
| pytest | `--junitxml=junit.xml` |
| Go | `go test -v \| go-junit-report > junit.xml` |

## gate.yml

**What it does**: Runs in the merge queue (after all PR checks pass). Downloads the evidence artifact, independently verifies everything, and writes a pass/fail summary to the dashboard.

**Trigger**: `merge_group` only. No race condition - the merge queue only activates when all PR checks are green.

**What it verifies**:

1. **Sigstore attestation** - cryptographic proof from the right workflow (can't be faked by a rogue workflow)
2. **JUnit XML test cases** - independently counts `<testcase>` elements (can't pass with empty/zero tests)
3. **Commit SHA** - evidence is from this exact commit
4. **Repository** - evidence is from this repo
5. **SBOM** - dependency inventory exists
6. **Build digest** - artifact integrity

**Error reporting**: When no evidence is found, the gate queries the GitHub API for failed CI steps and writes a detailed failure table to the job summary - zero extra CI minutes since the gate runs anyway.

**How to enable** (org admin, one time):

1. Go to `github.com/organizations/sonarmd/settings/rules`
2. New ruleset - target all repositories (or specific ones)
3. Target default branch
4. Add rule: "Require merge queue"
5. Add rule: "Require workflows to pass"
6. Add workflow: `sonarmd/workflows` -> `.github/workflows/gate.yml` -> ref: `main`

After this, every PR in the org must pass through the merge queue with valid evidence to merge.

## FAQ

**Can I split CI into multiple jobs?**
Yes. Put `ci-sign` at the end of whatever runs last. If you have parallel jobs, add a final job that `needs: [lint, test, build]` and only runs `ci-sign`.

**What if my project has no tests?**
`ci-sign` requires JUnit XML with at least one test case. The gate independently verifies this. You need at least one test.

**What if I need to run CI on self-hosted runners?**
Change `runs-on`. Nothing else changes. `ci-sign` is shell commands - it runs anywhere.

**Can someone bypass the gate?**
Not without org admin access to the ruleset. The gate is enforced at the org level via merge queue. Even repo admins can't skip it.

**Why Sigstore?**
Industry standard (SLSA). GitHub's native `actions/attest-build-provenance` produces cryptographic attestations tied to the specific workflow that ran. A rogue workflow produces a different signature. No custom JSON schema to maintain.

**Why merge queue instead of pull_request?**
Eliminates the race condition. With `pull_request`, the gate and CI both trigger simultaneously - the gate would fail because CI hasn't finished yet. The merge queue only activates after all PR checks pass, so the evidence always exists when the gate runs.

**What permissions do I need?**
Your CI workflow needs `id-token: write` and `attestations: write` for Sigstore signing. The gate needs `attestations: read`.
