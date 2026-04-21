# CI/CD Unification — Implementation Plan

**Date:** 2026-04-21
**Owner:** @avespoli
**Authority:** `~/.claude/directives/cicd.md`

## North star (from repo owner)

- `sonarmd/workflows` owns: orchestration, platform, deploy verbs, servers.
- Caller repos own: build, lint, tests. Nothing else.
- Hard boundaries. No repeated work. No validation where unnecessary.

## Target shape

### sonarmd/workflows
Exactly three workflows in `.github/workflows/`:
1. `ci-core.yml` — inputs `setup` + `steps`; runs, signs, verifies, preserves artifact; Slack on fail.
2. `cd-core.yml` — **no inputs**; discovers by SHA; tags commit, creates GH Release with bundle, pings Slack deploy channel.
3. `cicd-orchestrator.yml` — routes: PR → CI only; push to master/main/release/** → check for CI pass + artifact, run CI if missing, then CD.

Composite actions under `actions/<name>/action.yml` (repo root, not `.github/actions/`). Single-purpose, minimal inputs, callable in any order.

### Every caller repo
One file: `.github/workflows/ci.yml` — ~25-line wrapper calling `cicd-orchestrator.yml@main` with `setup` + `steps` inputs.

Plus `deploy.json` at repo root (schema already defined).

### Forbidden everywhere in callers
- `deploy.yml`
- `auto-tag.yml`
- `break-glass.yml`
- `cd.yml` (as a separate caller file)
- any other `*.yml` in `.github/workflows/`

---

## Phase 1 — Foundation: sonarmd/workflows collapse

**Branch:** `chore/cicd-collapse-to-three`
**Base:** `main`

### Current state (25 workflows)
```
auto-tag.yml             build-gate.yml           break-glass.yml
cd-core.yml ✓            cd.yml                   ci-cd-core.yml (orchestrator — rename)
ci-core.yml ✓            ci.yml                   deploy-api-ssm.yml
deploy-eas-build.yml     deploy-ecs.yml           deploy-gate.yml
deploy-s3-cloudfront.yml deploy.yml               dike-seal.yml
dike-verify.yml          gate.yml                 manual-deploy.yml
metrics-collector.yml    metrics-report.yml       notify-slack.yml
preflight.yml            static-analysis-gate.yml tag-release.yml
test-gate.yml
```

### Actions
1. **Rename** `ci-cd-core.yml` → `cicd-orchestrator.yml` (leave a stub at old path for one release that `uses: ./cicd-orchestrator.yml` so in-flight callers don't break; delete stub in Phase 2).
2. **Remove `ci_run_id` input from `cd-core.yml`.** cd-core discovers by SHA (fall back to legacy discovery is already there per code comment — make it the only path).
3. **Archive → zip, then remove** these workflow files. The zip preserves the original content for reference; the active workflows directory keeps only the canonical three. Zip naming: `archive/pre-collapse-workflows-2026-04-21.zip` at the repo root (NOT inside `.github/workflows/` — GHA will try to parse any file it sees there). Commit the zip in the same PR as the removals so the audit trail is a single diff. Files to archive:
   - `auto-tag.yml` (tag-release logic moves into `cd-core.yml` or a composite action)
   - `break-glass.yml`
   - `cd.yml` (duplicated by `cd-core.yml` + orchestrator)
   - `ci.yml` (duplicated by `ci-core.yml` + orchestrator)
   - `deploy.yml`
   - `manual-deploy.yml`
   - `*-gate.yml` (build-gate, deploy-gate, gate, static-analysis-gate, test-gate) — any required gating moves into `ci-core.yml` steps or composite actions
   - `deploy-api-ssm.yml`, `deploy-eas-build.yml`, `deploy-ecs.yml`, `deploy-s3-cloudfront.yml` — these are Ansible's job, not GHA's; dead
   - `dike-seal.yml`, `dike-verify.yml` — confirm dead with owner; if live, extract into composite actions
   - `metrics-collector.yml`, `metrics-report.yml` — confirm dead; if live, move to a scheduled job outside CI/CD
   - `notify-slack.yml` — functionality lives in `actions/notify-slack/` (composite), not a reusable workflow
   - `preflight.yml` — roll into `ci-core.yml` if needed
   - `tag-release.yml` — absorbed by `cd-core.yml`
4. **Keep only 3 files** at end of phase: `ci-core.yml`, `cd-core.yml`, `cicd-orchestrator.yml`.
5. **DECISIONS.md** at repo root, documenting the canonical shape + forbidden list (mirror of directive).

### Out of scope for Phase 1 (explicitly deferred)
- Actions consolidation (30 actions, many redundant: 3 slack variants, 3 ci status toggles, 4 tagging actions). Separate PR: `chore/actions-canonicalize`.
- `product-documentation`, `release-note-maintainer` action relevance review.

## Phase 2 — Caller migration

Each caller gets ONE PR reducing `.github/workflows/` to a single `ci.yml` using the canonical wrapper shape.

### Per-repo deltas

| Repo | Current state | PR scope |
|---|---|---|
| `triggr_api` | `ci.yml` (orchestrator, good), `auto-tag.yml`, `break-glass.yml`, `deploy.yml` | Archive the 3 forbidden files to `archive/pre-collapse-workflows-2026-04-21.zip` then remove from `.github/workflows/`. Update `ci.yml` `uses:` path `ci-cd-core.yml@main` → `cicd-orchestrator.yml@main`. Confirm `deploy.json` exists at root. |
| `infra-cdk` | `ci.yml`, `cd.yml`, `auto-tag.yml`, `break-glass.yml`, `cdk_wfs.zip` (existing archive) | Merge `ci.yml`+`cd.yml` concerns into one wrapper pointing at orchestrator. Archive the rest into a new zip (or append to `cdk_wfs.zip` if owner prefers), then remove. Verify `setup`/`steps` drive `cdk synth` + package. Confirm `deploy.json` describes the CDK deploy (synth JSON → S3 → CFN). |
| `frontend-patient-app` | `ci.yml`, `auto-tag.yml`, `break-glass.yml`, `deploy.yml` (on `release/v1.5.0`) | Archive the 3 forbidden files to `archive/pre-collapse-workflows-2026-04-21.zip` then remove. Point `ci.yml` at orchestrator. Confirm `deploy.json` exists. |
| `frontend` | `hotfix/skip-briteverify-email-check` has `cd.yml`, `ci.yml`, `frontendwfs.zip` (existing archive) + full `.circleci/`. Two stale migration branches exist: `feature/SONMD-2126-frontend-cicd-fix`, `feature/SONMD-2718-github-actions-migration` | (a) Pick one of the stale migration branches as source-of-truth (owner decision); rebase on latest master. (b) Land: 1 `ci.yml` + `deploy.json`. Archive `.circleci/` dir contents and any other workflows into a zip. (c) Ensure release branches are covered (CircleCI's gap — the orchestrator handles `release/**` natively so this is fixed by migration). |
| `triggr_misc` (mobile) | `feature/SONMD-2126-ansible-mobile` — no GHA files yet, CircleCI on main | Build from scratch using canonical wrapper. `steps` should do the local sanity build only (no EAS call from GHA). Ansible calls EAS with the git tag from the release bundle. Archive `.circleci/` dir contents, then remove. |

Each PR is tiny (1–2 files changed, multiple deleted). Each opens as draft against the repo's default base (`master` / `main`). Signed commits. Not merged until owner reviews.

## Phase 3 — Actions consolidation (deferred)

Separate branch + PR on `sonarmd/workflows`: `chore/actions-canonicalize`.

Targets:
- One `notify-slack` action. Delete `ping-slack`, `slack-notify`.
- One `ci-status` action (not three). Delete `ci-breaker`, `close-ci`, `open-ci`; replace with `ci-status` taking `state: open|close|break`.
- Tagging: merge `create-tag`, `resolve-build-tag`, `resolve-identifier`, `tagging-and-classification` into one or two focused actions. Owner to define canonical names.
- Review relevance: `product-documentation`, `release-note-maintainer`.
- Action README per action documenting inputs/outputs (generated once, maintained by contributors).

## Ordering / dependencies

1. **Phase 1 lands first** (sonarmd/workflows → 3 workflows). Callers cannot migrate cleanly until `cicd-orchestrator.yml` is the canonical entry point.
2. Phase 2 caller migrations run **in parallel** after Phase 1 merges. Each is independent.
3. Phase 3 action consolidation is **after Phase 2** — do not touch the actions catalog until the workflow shape is stable.

## Risk / rollback

- Phase 1 stub at the old `ci-cd-core.yml` path means any caller that hasn't migrated in Phase 2 continues to work. Grace period: one week after Phase 1 merges.
- cd-core's `ci_run_id` input is marked optional (`required: false, default: ''`); removing it is non-breaking if no caller relies on it. Grep callers before deleting.
- Every PR is draft until owner review. No merges without explicit approval.

## Rules observed

- Rule #1: plan written before code changes. This file.
- Rule #7: all PRs target `main`/`master`, not `main` force-merges.
- Rule #8: no drive-by changes. Each PR does exactly one migration.
- Rule #9: `DECISIONS.md` in `sonarmd/workflows` will capture the mandate before any Phase 1 code change.
- Rule #12: every commit signed.
- Rule #14: all PRs open as draft.
