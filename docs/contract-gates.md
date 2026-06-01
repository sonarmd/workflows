# Contract Gates

Central quality gates that validate CI/CD outputs with independently verified evidence. Gates define **contracts** - they never run project commands. Each repo does its own work and calls the gates at stage boundaries.

## Trust Model

The gates are unfakeable because of five interlocking guarantees:

1. **SHA identity** - `github.sha` uniquely identifies the code. Same SHA = same code. The gate runs at the same SHA as the CI that produced the evidence.

2. **Artifact scoping** - `actions/upload-artifact` ties files to the workflow run. `actions/download-artifact` in the gate only downloads from the same run. Artifacts cannot be injected from another run.

3. **Independent parsing** - The test gate downloads the JUnit XML artifact itself and counts `<testcase>` elements. It does not trust caller-provided counts. A repo that passes `test_result: success` but uploads an empty XML (or no artifact) is blocked.

4. **CODEOWNERS protection** - `.github/workflows/` is protected in each repo. Developers cannot remove gate calls or modify evidence collection steps without platform-eng approval.

5. **Branch protection** - Required status checks include the gate jobs. Merging is blocked until all gates pass.

## Gate Interfaces

### static-analysis-gate.yml

Validates that lint ran on real files and typecheck didn't fail.

```yaml
uses: sonarmd/workflows/.github/workflows/static-analysis-gate.yml@main
with:
  lint_result:      ${{ needs.lint.result }}       # required: 'success' | 'failure' | 'skipped'
  lint_file_count:  ${{ needs.lint.outputs.count }} # required: number > 0
  typecheck_result: ${{ needs.typecheck.result }}   # optional: default 'skipped'
```

| Input | Type | Required | Rules |
|-------|------|----------|-------|
| `lint_result` | string | yes | Must be `success`. Cannot be skipped. |
| `lint_file_count` | number | yes | Must be > 0. Prevents lint from running on zero files. |
| `typecheck_result` | string | no | `success` or `skipped` are fine. `failure` blocks. Default: `skipped`. |

**Output:** `gate_result` - `success` or `failure`

### test-gate.yml

Downloads JUnit XML test report artifacts and independently counts `<testcase>` elements. Does not trust caller-provided counts.

```yaml
uses: sonarmd/workflows/.github/workflows/test-gate.yml@main
with:
  test_result:     ${{ needs.test.result }}  # required
  report_artifact: test-report               # optional, default 'test-report'
```

| Input | Type | Required | Rules |
|-------|------|----------|-------|
| `test_result` | string | yes | Must be `success`. Cannot be skipped. |
| `report_artifact` | string | no | Name prefix for artifact(s). Default: `test-report`. Gate matches `test-report*`. |

**Output:** `gate_result` - `success` or `failure`

**Evidence requirements:**
- Upload JUnit XML as an artifact whose name starts with the `report_artifact` prefix
- The XML must contain at least one `<testcase>` element
- For matrix/sharded jobs, upload each shard separately (e.g., `test-report-shard-0`, `test-report-shard-1`)
- The gate downloads all matching artifacts and sums `<testcase>` counts across all XML files

### build-gate.yml

Validates the build succeeded. Phase 2 will add artifact signing and BOM verification.

```yaml
uses: sonarmd/workflows/.github/workflows/build-gate.yml@main
with:
  build_result: ${{ needs.build.result }}  # required
```

| Input | Type | Required | Rules |
|-------|------|----------|-------|
| `build_result` | string | yes | `success` or `skipped` passes. `failure` blocks. |
| `commit_sha` | string | no | Phase 2: for artifact signature verification. |
| `artifact_name` | string | no | Phase 2: for artifact validation. |

**Output:** `gate_result` - `success` or `failure`

### deploy-gate.yml

Final checkpoint before deployment. Requires all upstream gates.

```yaml
uses: sonarmd/workflows/.github/workflows/deploy-gate.yml@main
with:
  static_analysis_gate_result: ${{ needs.static-analysis-gate.outputs.gate_result }}
  test_gate_result:            ${{ needs.test-gate.outputs.gate_result }}
  build_gate_result:           ${{ needs.build-gate.outputs.gate_result }}
```

| Input | Type | Required | Rules |
|-------|------|----------|-------|
| `static_analysis_gate_result` | string | yes | Must be `success`. |
| `test_gate_result` | string | yes | Must be `success`. |
| `build_gate_result` | string | yes | `success` or `skipped` passes. |

**Output:** `gate_result` - `success` or `failure`

## JUnit XML Format

The test gate parses JUnit XML - a universal format supported by every major test framework. It counts `<testcase>` elements using `grep -c '<testcase'`.

### Producing JUnit XML

| Framework | Configuration |
|-----------|--------------|
| Jest | `yarn test --reporters=default --reporters=jest-junit` (requires `jest-junit` devDependency) |
| pytest | `pytest --junitxml=junit.xml` |
| Mocha | `mocha --reporter mocha-junit-reporter` or convert from JSON (see triggr_api template) |
| Cypress | Configure `cypress-junit-reporter` |

### Uploading the Artifact

```yaml
- name: Upload test report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: test-report
    path: junit.xml
    if-no-files-found: warn
```

Use `if: always()` so the report uploads even on test failure - the gate checks `test_result` for pass/fail, the artifact provides evidence of what actually ran.

### Matrix / Sharded Jobs

Upload each shard with a unique artifact name. The gate pattern-matches all of them:

```yaml
# In each matrix job:
- uses: actions/upload-artifact@v4
  if: always()
  with:
    name: test-report-shard-${{ matrix.shard }}
    path: junit.xml
    if-no-files-found: warn
```

The gate downloads all artifacts matching `test-report*`, each into its own subdirectory, and counts `<testcase>` elements across all XML files.

### Converting Mocha JSON to JUnit XML

For projects using Mocha's `--reporter json`, convert the output without adding new dependencies:

```yaml
- name: Generate JUnit XML
  if: always()
  run: |
    python3 -c "
    import json, html
    d = json.load(open('mocha-results.json'))
    lines = ['<?xml version=\"1.0\"?>', '<testsuites>']
    lines.append('<testsuite tests=\"%d\" failures=\"%d\">' % (d['stats']['tests'], d['stats']['failures']))
    for t in d.get('passes', []) + d.get('failures', []) + d.get('pending', []):
        name = html.escape(t.get('fullTitle', ''))
        cls = html.escape(t.get('file', ''))
        lines.append('<testcase name=\"%s\" classname=\"%s\"/>' % (name, cls))
    lines.append('</testsuite></testsuites>')
    open('junit.xml', 'w').write('\n'.join(lines))
    " 2>/dev/null || true
```

## CI Wrapper (ci.yml)

For projects that can express their CI as simple shell commands, the `ci.yml` wrapper handles evidence collection and gate routing automatically:

```yaml
jobs:
  ci:
    uses: sonarmd/workflows/.github/workflows/ci.yml@main
    with:
      node_version:       '18'
      lint_command:        yarn lint
      test_command:        yarn test --ci --reporters=default --reporters=jest-junit
      typecheck_command:   yarn tsc --noEmit
      build_command:       yarn build
      lint_glob:           'src/**/*.{ts,tsx}'
      test_report_path:   junit.xml
```

The wrapper:
1. Sets up the runtime (Node.js or Python)
2. Runs lint with file counting
3. Runs typecheck (optional)
4. Runs tests and uploads JUnit XML artifact
5. Runs build (optional)
6. Calls static-analysis-gate and test-gate with the collected evidence

For projects that **cannot** use the wrapper (service containers, matrix sharding, monorepo path filtering, etc.), call the gates directly. See the per-repo templates for examples.

## Monorepo Pattern (Path Filtering)

The frontend monorepo only tests apps that changed. This creates an edge case: when no apps change, no test jobs run, and no artifacts exist.

Solution: the summarize job uploads a **synthetic JUnit XML** documenting that change detection verified nothing needed testing:

```xml
<?xml version="1.0"?>
<testsuites>
  <testsuite name="change-detection" tests="1" failures="0">
    <testcase name="no-frontend-changes-detected" classname="ci.change-detection"/>
  </testsuite>
</testsuites>
```

This gives the test gate an artifact to parse (1 testcase = evidence exists), while clearly documenting what happened.

## Deploy Workflow Pattern

Deploy workflows are tag-triggered. CI gates already passed on the commit the tag points to, so the deploy workflow passes `success` for the CI gates and validates the build gate from the deploy build:

```yaml
jobs:
  build:
    steps:
      - run: yarn build
      - uses: actions/upload-artifact@v4
        with: { name: build-artifact, path: dist/ }

  build-gate:
    needs: build
    if: always()
    uses: sonarmd/workflows/.github/workflows/build-gate.yml@main
    with:
      build_result: ${{ needs.build.result }}

  deploy-gate:
    needs: build-gate
    if: always()
    uses: sonarmd/workflows/.github/workflows/deploy-gate.yml@main
    with:
      static_analysis_gate_result: success  # CI already passed
      test_gate_result:            success  # CI already passed
      build_gate_result: ${{ needs.build-gate.outputs.gate_result }}

  deploy:
    needs: deploy-gate
    if: needs.deploy-gate.outputs.gate_result == 'success'
    steps:
      - # Deploy however the repo wants
```

## CODEOWNERS

Protect `.github/workflows/` in every repo to prevent unauthorized removal of gate calls:

```
# .github/CODEOWNERS
.github/workflows/ @sonarmd/platform-eng
```

## Gate Output Format

Every gate prints a formatted summary to the workflow log:

```
---------------------------------------------
  Test Gate
  repo:   sonarmd/triggr_api
  sha:    abc123f
  run:    12345678
---------------------------------------------

  [OK]  test-status      passed
  [OK]  test-report      artifact downloaded
  [OK]  test-evidence    847 tests verified from report

---------------------------------------------
  Test gate passed - 847 tests independently verified
```

When a gate blocks:

```
  [FAIL]  test-evidence    BLOCKED - zero <testcase> elements in report
```

## Phase 2 (Future)

Once the gate pattern is established:

- `build-gate.yml` downloads the build artifact and verifies:
  1. Artifact exists and is non-empty
  2. Cosign/sigstore signature matches the commit SHA
  3. CycloneDX BOM references the same artifact hash
- `build-gate.yml` persists validated artifacts to S3 (durable storage)
- `deploy-gate.yml` verifies the artifact in S3 matches what was gated
- Each repo adds signing + BOM generation to its build job (via shared composite action)
