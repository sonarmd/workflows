# Migration Runbook

## Contract Gates Migration

Migrating from the old imperative CI wrappers (`ci-node.yml`, `gate.yml`) to the contract-based gate system.

### Prerequisites

- [ ] `sonarmd/workflows` has the 4 gate workflows on `main`
- [ ] CODEOWNERS protects `.github/workflows/` in every repo
- [ ] Branch protection requires the gate status checks
- [ ] `jest-junit` is a devDependency in all Jest-based projects

### Migration Order

1. **Land gate workflows** in `sonarmd/workflows` (no breaking changes — new files only)
2. **frontend-patient-app** first (smallest repo, cleanest template)
3. **triggr_api** second (custom CI already, just add artifact uploads + gate calls)
4. **frontend** third (monorepo, most complex — path filtering + synthetic reports)
5. **Deprecate `gate.yml`** after all consumers migrated
6. **Delete `ci-node.yml`** (already removed in this branch)

### Per-Repo Migration Steps

For each repository:

1. **Add `jest-junit` devDependency** (if using Jest):
   ```bash
   yarn add --dev jest-junit
   ```

2. **Update test commands** to produce JUnit XML:
   - Jest: add `--reporters=default --reporters=jest-junit`
   - Mocha: add JSON->XML conversion step (see triggr_api template)
   - pytest: add `--junitxml=junit.xml`

3. **Add artifact upload** after the test step:
   ```yaml
   - uses: actions/upload-artifact@v4
     if: always()
     with:
       name: test-report
       path: junit.xml
       if-no-files-found: warn
   ```

4. **Add lint file count** to the lint step:
   ```yaml
   - run: |
       FILE_COUNT=$(find src -type f \( -name '*.ts' -o -name '*.tsx' \) | wc -l | tr -d ' ')
       echo "file_count=$FILE_COUNT" >> "$GITHUB_OUTPUT"
   ```

5. **Replace gate calls**:
   ```diff
   - uses: sonarmd/workflows/.github/workflows/gate.yml@main
   + uses: sonarmd/workflows/.github/workflows/static-analysis-gate.yml@main
     with:
       lint_result:     ${{ needs.lint.result }}
   +   lint_file_count: ${{ needs.lint.outputs.file_count }}

   + uses: sonarmd/workflows/.github/workflows/test-gate.yml@main
   + with:
   +   test_result: ${{ needs.test.result }}
   ```

6. **Remove stale outputs** — drop `test_count` from job outputs and gate inputs

7. **Add deploy gates** to deploy workflows (build-gate + deploy-gate chain)

### Validation

After each repo migration:

```bash
# Verify gate checks appear
gh run list --repo sonarmd/<repo> --workflow ci.yml --limit 3

# Check gate output in the run log
gh run view <run-id> --repo sonarmd/<repo> --log | grep -A 20 "Test Gate"
```

### Rollback

Each repo can independently revert by restoring the previous `.github/workflows/` files. The old `gate.yml` remains available (deprecated but functional) during the migration period.

---

## CircleCI to GitHub Actions Migration

Original migration from CircleCI. Kept for reference.

### Phase 1: Frontend CI

1. Copy `per-repo/frontend/.github/workflows/ci.yml` to `sonarmd/frontend`
2. Open PR — GHA CI runs alongside CircleCI
3. Verify same tests pass/fail, timing comparable
4. Merge to staging

### Phase 2: Frontend Deploy

1. Copy `per-repo/frontend/.github/workflows/deploy.yml`
2. Set repository secrets
3. Test dev deploy first, then staging, then production
4. Disable CircleCI deploy jobs one at a time

### Phase 3: API CI

1. Copy `per-repo/triggr_api/.github/workflows/ci.yml`
2. Verify 4-shard parallelism + MongoDB service container
3. Verify GraphicsMagick installs correctly

### Phase 4: API Deploy

1. Copy `per-repo/triggr_api/.github/workflows/deploy.yml`
2. Test each environment sequentially
3. Verify OIDC + ECS deployment chain

### Phase 5: Mobile App

1. Copy `per-repo/frontend-patient-app/.github/workflows/`
2. Test preview build with staging tag
3. Test production build + auto-submit

### Phase 6: Cleanup

- [ ] Remove `.circleci/` from all repos
- [ ] Decommission CircleCI project connections
- [ ] Remove deprecated `gate.yml` from `sonarmd/workflows`

### Safety: Parallel Running

Both systems coexist safely during migration. CircleCI and GitHub Actions use different workflow files. To avoid double-deploys, disable CircleCI deploy jobs before enabling the GHA equivalents.
