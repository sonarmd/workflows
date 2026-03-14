# sonarmd/workflows

CI enforcement for SonarMD. Two pieces:

1. **`ci-sign`** — composite action. Add as the last step in your CI. Writes an attestation proving CI passed at this commit.
2. **`gate.yml`** — required workflow (org-level ruleset). Runs automatically on every PR. Checks for the attestation. No attestation = no merge.

You own your CI. Install whatever you want, run whatever you want. The only requirement is `ci-sign` at the end.

## How It Works

```
Your CI workflow:
  checkout → setup → install deps → lint → test → build → ci-sign
                                                              ↓
                                                     uploads attestation.json
                                                              ↓
gate.yml (runs automatically):
  downloads attestation → verifies commit SHA → PASS or FAIL
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

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # === Your setup — install whatever you need ===
      - uses: actions/setup-node@v4
        with:
          node-version: '18'
      - run: yarn install --frozen-lockfile

      # === Your checks — run whatever you run ===
      - run: yarn lint
      - run: yarn test
      - run: yarn build

      # === ci-sign — MUST be last ===
      - uses: sonarmd/workflows/actions/ci-sign@main
```

That's it. The gate runs automatically.

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
      - run: yarn test
        env:
          LOG_LEVEL: none
          TZ: utc
      - uses: sonarmd/workflows/actions/ci-sign@main
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
      - run: yarn just-test
      - uses: sonarmd/workflows/actions/ci-sign@main
```

### frontend-patient-app

React Native / Expo. Node 22. No build step — production builds go through EAS.

```yaml
name: CI

on:
  push:
    branches: ['**']
  pull_request:
    branches: [master, staging, 'release/**']

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
      - run: yarn test --ci --passWithNoTests
      - uses: sonarmd/workflows/actions/ci-sign@main
```

## Structure

```
actions/
  ci-sign/action.yml       The attestation action — one step, one JSON file

.github/workflows/
  gate.yml                 Required workflow — runs automatically, verifies attestation

per-repo/                  Ready-to-copy CI workflows for each project
  triggr_api/
  frontend/
  frontend-patient-app/
  triggr_misc/
```

## ci-sign

**What it does**: Writes `attestation.json` with commit SHA, repo, timestamp, schema version. Uploads it as the `ci-attestation` artifact.

**Inputs**: None.

**When to call it**: As the last step in your CI job. If you have multiple jobs, put it at the end of the one that runs last.

**Schema** (`sonarmd/ci-attestation/v1`):

```json
{
  "schema": "sonarmd/ci-attestation/v1",
  "commit": "abc123...",
  "ref": "refs/pull/42/merge",
  "repository": "sonarmd/triggr_api",
  "run_id": "12345678",
  "run_attempt": "1",
  "actor": "avespoli-sonarmd",
  "timestamp": "2026-03-14T12:00:00Z"
}
```

## gate.yml

**What it does**: Downloads the `ci-attestation` artifact for this commit via the GitHub API. Verifies:
- Attestation exists (ci-sign was called = all prior steps passed)
- Commit SHA matches (evidence is from this exact commit)
- Repository matches (evidence is from this repo)
- Schema is `sonarmd/ci-attestation/v1`

**How to enable** (org admin, one time):
1. Go to `github.com/organizations/sonarmd/settings/rules`
2. New ruleset → target all repositories (or specific ones)
3. Target default branch
4. Add rule: "Require workflows to pass"
5. Add workflow: `sonarmd/workflows` → `.github/workflows/gate.yml` → ref: `main`

After this, every PR in the org must have a valid attestation to merge. Projects never add the gate — it's automatic.

## FAQ

**Can I split CI into multiple jobs?**
Yes. Put `ci-sign` at the end of whatever runs last. If you have parallel jobs, add a final job that `needs: [lint, test, build]` and only runs `ci-sign`.

**What if my project has no tests?**
That's between you and your tech lead. `ci-sign` doesn't check what you ran — it only proves that everything before it succeeded. If your workflow is just `checkout → lint → ci-sign`, the attestation says lint passed.

**What if I need to run CI on self-hosted runners?**
Change `runs-on`. Nothing else changes. `ci-sign` is shell commands — it runs anywhere.

**Can someone bypass the gate?**
Not without org admin access to the ruleset. The gate is enforced at the org level. Even repo admins can't skip it.

**What if I move off GitHub Actions?**
Your CI steps are just shell commands — they run on any CI platform. Replace `ci-sign` with writing the same JSON and uploading it as an artifact on your new platform. The attestation schema is just JSON.
