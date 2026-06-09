# SonarMD CI/CD Platform Specification

Authoritative, single-source specification. Implementation must match this document exactly.

---

## 1. Architecture

```
PR -> ci-core (setup + steps + validate + bundle-pipeline) -> merge
  -> cd-core (tag + release + deploy <env> <identifier> <url>) -> Ansible
```

Three workflows:
- `ci-core.yml` - validation, packaging, release evidence
- `cd-core.yml` - tag, release, handoff to Ansible via Slack
- `break-glass.yml` - emergency recovery for trusted artifacts

GitHub Actions is NOT the deploy authority. Ansible is.

---

## 2. Repo Contract

### Repos MAY:
1. Define `setup` shell (environment prep)
2. Define `steps` shell (lint, test, build)
3. Define `deploy.json` (bundle declaration)
4. Choose build output directory
5. Produce bundle output

### Repos MAY NOT control:
- **Deploy identity (identifier)** - platform-owned via `.github/repo-identity.yml`
- Environment selection
- Slack routing or channels
- Deployment behavior
- Packaging logic
- Signing
- Release structure
- Manifest file name or path
- Secrets model / 1Password configuration
- CD inputs of any kind

### Identifier Authority
The deploy identifier (api, fe, mobile, etc.) is derived from the platform-owned
mapping in `.github/repo-identity.yml`, keyed by `github.repository.name`.
If `deploy.json.identifier` exists, it MUST match the platform mapping or CD fails.
Repos cannot choose or change their own deploy identity.

### Repo CI wrapper (complete):
```yaml
name: CI
on:
  pull_request:
    branches: [master, staging, 'release/**']
  merge_group:
    branches: [master, staging, 'release/**']
jobs:
  ci:
    uses: sonarmd/workflows/.github/workflows/ci-core.yml@main
    with:
      setup: |
        # repo-specific setup
      steps: |
        # repo-specific lint, test, build
    secrets: inherit
```

### Repo CD wrapper (complete):
```yaml
name: CD
on:
  push:
    branches: [master, 'release/**']
jobs:
  cd:
    uses: sonarmd/workflows/.github/workflows/cd-core.yml@main
    secrets: inherit
```

No inputs to CD. Zero.

---

## 3. deploy.json Schema

File MUST exist at repo root. Name MUST be `deploy.json`.

```json
{
  "app": "triggr-api",
  "identifier": "api",
  "build_root": "dist",
  "bundles": [
    {
      "name": "api",
      "path": "dist/api",
      "target": "ec2",
      "hosts": {
        "api-primary": "api-01.${env}.internal",
        "api-secondary": "api-02.${env}.internal"
      }
    },
    {
      "name": "worker-lambda",
      "path": "dist/worker-lambda",
      "target": "lambda",
      "hosts": {
        "worker": "worker-${env}"
      }
    }
  ]
}
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `app` | string | yes | Application name |
| `identifier` | string | yes | Short identifier for tag/release naming |
| `build_root` | string | no | Build output root directory (default: `dist`) |
| `bundles` | array | yes | Bundle declarations |
| `bundles[].name` | string | yes | Unique bundle name |
| `bundles[].path` | string | yes | Bundle directory path relative to build root |
| `bundles[].target` | enum | yes | `s3`, `ec2`, `eas`, `cdk`, `lambda`, `fargate` |
| `bundles[].hosts` | object | yes | Label -> Ansible inventory match key |

### Rules

- `app` - required, non-empty string
- `identifier` - required, pattern `^[a-z][a-z0-9_-]{0,31}$`
- `bundles` - required, minimum 1 item
- `bundles[].name` - unique within manifest, pattern `^[a-z][a-z0-9_-]{0,63}$`
- `bundles[].path` - non-empty, relative path
- `bundles[].target` - ONLY: `s3`, `ec2`, `eas`, `cdk`, `lambda`, `fargate`. Anything else -> FAIL
- `bundles[].hosts` - required, non-empty object. Values must be unique within bundle. Values are opaque Ansible inventory match keys - NOT DNS, NOT networking
- Template variables - ONLY `${env}` is allowed. No other dynamic templating.
- `additionalProperties: false` at all levels

---

## 4. Build Output Model

The repo produces build output in a build root directory (default: `./dist`).

### Mode 1 - Multi-bundle

If the build root contains subdirectories:
```
./dist/
  api/          -> bundle "api"
  lambda1/      -> bundle "lambda1"
  lambda2/      -> bundle "lambda2"
```

Rules:
- Each top-level subdirectory = one bundle
- Each MUST be declared in deploy.json
- Each bundle = exactly one target
- Every declared bundle path MUST exist
- Every actual subdirectory MUST be declared
- Mismatch in either direction -> FAIL

### Mode 2 - Single-bundle

If the build root contains NO subdirectories:
```
./dist/
  index.js
  package.json
  ...
```

Rules:
- Treated as ONE bundle
- deploy.json MUST contain exactly ONE bundle
- That bundle's `path` is the build root itself
- If multiple bundles are declared -> FAIL

---

## 5. CI Execution Flow

Exact sequence (normative):

```
1.  timeout-handler
2.  start-monitoring
3.  checkout
4.  open-ci

5.  run-shell-block(setup)
6.  run-shell-block(steps)

7.  validate-release-contract    <- schema validation
8.  validate-build-output        <- structure alignment

9.  bundle-pipeline              <- per-bundle packaging

10. close-ci
```

### CI-core inputs (complete list):
```
setup:             multi-line shell (optional)
steps:             multi-line shell (required)
build_output_dir:  path (default: dist)
timeout:           minutes (default: 15, max: 30)
working_directory: path (default: .)
test_report_path:  JUnit XML path (default: junit.xml)
```

No other inputs. No runtime. No identifier. No slack. No mongo. No environment.

---

## 6. Bundle Pipeline

The bundle-pipeline action executes EXACTLY this:

```
mkdir ./release

for each bundle in deploy.json:

  1. validate bundle directory exists at build_output_dir/bundle.path
  2. validate target is in allowed enum
  3. validate hosts is non-empty object with unique values

  4. generate SBOM for this bundle
  5. generate SHA512 of all files in bundle
  6. generate checksum file
  7. generate aggregate digest

  8. create bundle manifest:
     ./release/<name>.manifest.json
     {
       "name": "<name>",
       "target": "<target>",
       "hosts": { ... },
       "sha512": "<aggregate>",
       "file_count": N,
       "commit": "<sha>",
       "timestamp": "<iso>"
     }

  9. tar bundle -> ./release/<name>.tar.gz
 10. emit: ./release/<name>.sbom.json
 11. emit: ./release/<name>.sha512
 12. emit: ./release/<name>.checksum

 13. sign ./release/<name>.tar.gz (Sigstore attestation)

after loop:

  14. assert all declared bundles were processed
  15. tar ./release -> release.tar.gz
  16. generate release.tar.gz.sha512
  17. generate release.tar.gz.checksum
  18. sign release.tar.gz (Sigstore attestation)
  19. upload artifact as "release"
```

### Per-bundle artifacts produced:
```
./release/
  api.tar.gz
  api.manifest.json
  api.sbom.json
  api.sha512
  api.checksum
  worker-lambda.tar.gz
  worker-lambda.manifest.json
  worker-lambda.sbom.json
  worker-lambda.sha512
  worker-lambda.checksum
```

### Outer release:
```
release.tar.gz          <- contains entire ./release/ directory
release.tar.gz.sha512
release.tar.gz.checksum
```

---

## 7. CD Flow

Exact sequence:

```
1.  timeout-handler
2.  start-monitoring
3.  load secrets (1Password)
4.  generate GitHub App token
5.  checkout (fetch-depth: 0)
6.  resolve identifier from platform mapping (.github/repo-identity.yml)
7.  resolve env + version + build number (see Release Lifecycle below)
8.  download CI artifact for this commit
9.  verify artifact checksums
10. create annotated git tag
11. create GitHub Release (draft prerelease for stg, full release for prd)
12. send Slack: deploy <env> <identifier> <deploy_tag> <artifact_url>
13. cut next release branch (prd only, bumps minor version)
```

NO repo inputs. Zero. Identifier from platform mapping, version from branch name.

### Tag format:
```
{env}-{identifier}-v{version}-b{build}
```
Examples: `stg-api-v1.0.0-b1`, `prd-api-v1.0.0-b2`, `stg-fe-v2.1.0-b1`

---

## 7.1 Release Lifecycle

### Release branch naming
```
release/v1.0.0
release/v4.2.3
```
Pattern: `^release\/v([0-9]+\.[0-9]+\.[0-9]+)$`

### Version authority
- **Staging**: release branch name is the version source (`release/v1.0.0` -> `1.0.0`)
- **Production**: version is derived from the **merged release branch**, NOT from
  "latest staging tag". Detection order:
  1. GitHub PR event source branch (`github.event.pull_request.head.ref`) - preferred
  2. Merge commit message parsing (fallback)
  3. Second parent branch inspection (fallback)
  4. Merged branch containment (last resort)
  If the source branch cannot be determined by any method, CD fails.
- package.json is NOT used for tag construction

### Build number
- Per-repo + per-version, computed from existing tags: `*-{identifier}-v{version}-b*`
- First build = b1, increments monotonically
- **Shared across stg and prd**: build numbers for the same identifier + version
  form ONE sequence regardless of environment. Example:
  - `stg-api-v1.0.0-b1` (first staging)
  - `prd-api-v1.0.0-b2` (production gets next number)
  - `stg-api-v1.0.0-b3` (another staging build)
- This ensures every build number is globally unique per repo+version
- Resets when version changes (v1.1.0 starts at b1)
- Tags are explicitly fetched (`git fetch --tags --force`) before computation

### Staging flow
1. PR merged into `release/v1.0.0`
2. CD resolves: env=stg, version=1.0.0, build=next
3. Tag: `stg-api-v1.0.0-b1`
4. GitHub Release: draft prerelease
5. Slack: `deploy stg api stg-api-v1.0.0-b1 <artifact_url>`

### Production flow
1. PR merged from `release/v1.0.0` into `master`
2. CD resolves: env=prd, version=1.0.0 (from merged release branch), build=next
3. Tag: `prd-api-v1.0.0-b2`
4. GitHub Release: full production release
5. Slack: `deploy prd api prd-api-v1.0.0-b2 <artifact_url>`

### Next release branch
After successful production CD:
- Current: v1.0.0 -> Next: v1.1.0 (bump minor, zero patch)
- Creates `release/v1.1.0` explicitly from `origin/master`
- Skips if branch already exists
- Initial commit tagged `[skip ci]`

---

## 8. Deployment Model (Ansible)

Ansible receives from Slack:
```
deploy <env> <identifier> <deploy_tag> <artifact_url>
```
Example: `deploy prd api prd-api-1.0.0-b77 https://api.github.com/...`

Ansible then:
1. Downloads `release.tar.gz` from GitHub Release
2. Verifies: checksum, SHA512
3. Extracts release
4. For each bundle:
   - Validates bundle tarball exists
   - Validates manifest
   - Validates checksum
   - Validates target
   - Deploys ONLY after all validation passes

Hosts in deploy.json are Ansible inventory match keys. Resolution happens in Ansible, not in GitHub Actions.

---

## 9. Failure Classification

All failures include: what, where, why, failing command, classification.

| Classification | When |
|---------------|------|
| `user-code` | Lint or code errors |
| `test` | Test runner failures |
| `build` | Build tool failures |
| `dependency-resolution` | Package install failures |
| `environment` | System dep issues |
| `release-contract` | deploy.json schema violation |
| `packaging` | Bundle pipeline failures |
| `policy` | Build structure mismatch |
| `timeout` | Time limit exceeded |
| `external-service` | Registry or API unreachable |
| `infrastructure/platform` | Runner or GHA issues |

---

## 10. Enforcement Rules

1. deploy.json MUST exist at repo root
2. deploy.json MUST validate against schema
3. Build output MUST align with bundle declarations
4. Every declared bundle MUST exist on disk
5. Every disk bundle MUST be declared
6. Targets MUST be in enum: s3, ec2, eas, cdk, lambda, fargate
7. Hosts MUST be non-empty with unique values
8. Only `${env}` template variable allowed
9. SHA512 for all checksums
10. Per-bundle signing via Sigstore
11. Repos get setup + steps + build_output_dir. Nothing else.
12. CD reads identifier from platform mapping. No repo input.
13. Version from release branch name, NOT package.json
14. Build numbers per-repo+version, computed from existing tags
