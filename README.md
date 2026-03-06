# sonarmd/workflows

Central CI/CD infrastructure for SonarMD. Defines **contracts** (gates), not implementations. Each repo does its own work and calls the gates at stage boundaries. The gates validate outputs with independently verified evidence.

## Architecture

```
repo runs lint/typecheck ──> static-analysis-gate.yml ──> validates evidence
repo runs tests          ──> test-gate.yml             ──> downloads JUnit XML, counts <testcase>
repo runs build          ──> build-gate.yml            ──> validates build status
                             deploy-gate.yml            ──> requires all 3 upstream gates
```

Repos are responsible for their own runtime (Node version, test framework, build tool). The gates only care about **results and evidence**.

## Structure

```
.github/workflows/              Reusable workflows
  static-analysis-gate.yml        Gate: lint (required) + typecheck (optional)
  test-gate.yml                   Gate: downloads JUnit XML, independently verifies test count
  build-gate.yml                  Gate: build validation (Phase 2: artifact signing)
  deploy-gate.yml                 Gate: requires all upstream gates before deploy
  ci.yml                          Convenience CI wrapper for simple projects
  deploy-s3-cloudfront.yml        Deploy utility: S3 sync + CloudFront invalidation
  deploy-eas-build.yml            Deploy utility: EAS Build (mobile)
  deploy-api-ssm.yml              Deploy utility: SSM-based API deployment
  notify-slack.yml                Slack deploy notifications
  metrics-collector.yml           Deploy metrics collection
  tag-release.yml                 Auto-tag on merge

actions/                         Composite actions
  setup-node/                      Node.js + yarn install + caching
  detect-changed-apps/             Path filtering for frontend monorepo

per-repo/                        Workflow templates for each repository
  frontend/                        sonarmd/frontend
  triggr_api/                      sonarmd/triggr_api
  frontend-patient-app/            sonarmd/frontend-patient-app

docs/                            Documentation
  contract-gates.md                Gate interfaces, trust model, evidence requirements
  architecture.md                  System architecture overview
  migration-runbook.md             CircleCI -> GHA migration steps
  system-diagrams.md               Deployment flow diagrams
```

## Quick Start

### Simple project (use the CI wrapper)

```yaml
# .github/workflows/ci.yml
jobs:
  ci:
    uses: sonarmd/workflows/.github/workflows/ci.yml@main
    with:
      node_version:      '18'
      lint_command:       yarn lint
      test_command:       yarn test --ci --reporters=default --reporters=jest-junit
      typecheck_command:  yarn tsc --noEmit
      build_command:      yarn build
      lint_glob:          'src/**/*.{ts,tsx}'
```

The wrapper handles evidence collection and gate routing automatically.

### Complex project (call gates directly)

```yaml
# .github/workflows/ci.yml
jobs:
  lint:
    steps:
      - run: yarn lint
      # Count files for evidence
      - run: echo "file_count=$(find src -type f -name '*.ts' | wc -l)" >> "$GITHUB_OUTPUT"

  test:
    steps:
      - run: yarn test --ci --reporters=default --reporters=jest-junit
      # Upload JUnit XML — the test gate parses this independently
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-report
          path: junit.xml

  static-analysis-gate:
    needs: [lint]
    if: always()
    uses: sonarmd/workflows/.github/workflows/static-analysis-gate.yml@main
    with:
      lint_result:     ${{ needs.lint.result }}
      lint_file_count: ${{ needs.lint.outputs.file_count }}

  test-gate:
    needs: [test]
    if: always()
    uses: sonarmd/workflows/.github/workflows/test-gate.yml@main
    with:
      test_result: ${{ needs.test.result }}
```

## Gates

| Gate | What it validates | Evidence |
|------|------------------|----------|
| `static-analysis-gate` | Lint passed, files were analyzed, typecheck didn't fail | `lint_file_count > 0` |
| `test-gate` | Tests passed, real tests exist | Downloads JUnit XML, counts `<testcase>` elements |
| `build-gate` | Build succeeded (or skipped for non-build repos) | Status check |
| `deploy-gate` | All upstream gates passed | Requires static-analysis + test + build gates |

The test gate is **artifact-based** — it downloads the JUnit XML report and independently counts test cases. It does not trust caller-provided counts. See [docs/contract-gates.md](docs/contract-gates.md) for the full trust model.

## Per-Repo Templates

Copy the appropriate `per-repo/<name>/.github/workflows/` directory to each repository's `.github/workflows/`. CODEOWNERS should protect these files to prevent unauthorized changes to gate calls.

| Repo | CI Pattern | Deploy Pattern |
|------|-----------|---------------|
| `frontend` | Monorepo path filtering, per-app test jobs, summarize + gates | S3 sync per app, build-gate + deploy-gate |
| `triggr_api` | 4-shard parallel tests with MongoDB, mocha JSON->JUnit XML | OIDC + ECS, build-gate + deploy-gate |
| `frontend-patient-app` | Jest + jest-junit, separate lint/typecheck/test jobs | EAS Build (tag-triggered), deploy-gate |

## GitHub Secrets Required

| Secret | Repos | Purpose |
|--------|-------|---------|
| `AWS_ACCESS_KEY_ID` | frontend | S3 deploy credentials |
| `AWS_SECRET_ACCESS_KEY` | frontend | S3 deploy credentials |
| `SLACK_WEBHOOK_URL` | all | Slack deploy notifications |
| `EXPO_TOKEN` | frontend-patient-app | EAS CLI authentication |
| `OP_SERVICE_ACCOUNT_TOKEN` | triggr_api | 1Password service account for config generation |
