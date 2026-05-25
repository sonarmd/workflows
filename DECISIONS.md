# DECISIONS

Architectural decisions for `sonarmd/workflows`. Per global rule #9, check here
before reverting or modifying any existing pattern. If a decision contradicts
what you think is correct, ASK — do not silently revert.

---

## 2026-04-21 — CI/CD is THREE workflows. Nothing more.

**Decision:** `sonarmd/workflows/.github/workflows/` contains exactly three
files. No exceptions, no "temporarily," no "for this one repo," no
"for backward compatibility."

1. `ci-core.yml` — CI only. Inputs: `setup`, `steps`. Signs + preserves artifact. Slack on fail.
2. `cd-core.yml` — CD only. **No inputs.** Discovers by SHA. Tags commit, creates GH Release with the CI artifact bundle, pings Slack deploy channel.
3. `cicd-orchestrator.yml` — routes: PR → CI only; push to master/main/release/** → reuse CI artifact if present, else run CI, then CD.

All other logic (signing, tagging, slack formatting, artifact download, etc.)
is a composite action under `actions/<name>/action.yml` at the repo root.

**Rationale:** `sonarmd/workflows` owns orchestration, platform, deploy verbs,
servers. Caller repos own their build, lint, tests. Hard boundaries. No
repeated work. No validation where unnecessary. Every caller's workflow file
looks the same — a thin wrapper passing `setup` + `steps` to the orchestrator.

**Forbidden files in caller repos** (delete on sight, never re-add):
- `deploy.yml`
- `auto-tag.yml`
- `break-glass.yml` (if reintroduced, it lives here, not in callers)
- `cd.yml`
- Any non-canonical workflow in `.github/workflows/`

**Archived and removed from this repo on 2026-04-21** (or planned in
`chore/cicd-collapse-to-three`). Files are zipped to
`archive/pre-collapse-workflows-2026-04-21.zip` at the repo root before being
removed from `.github/workflows/`, so the original work is preserved in the
history as a single committed artifact rather than scattered across the diff: `auto-tag.yml`, `break-glass.yml`,
`build-gate.yml`, `cd.yml`, `ci.yml`, `deploy-api-ssm.yml`,
`deploy-eas-build.yml`, `deploy-ecs.yml`, `deploy-gate.yml`,
`deploy-s3-cloudfront.yml`, `deploy.yml`, `dike-seal.yml`, `dike-verify.yml`,
`gate.yml`, `manual-deploy.yml`, `metrics-collector.yml`,
`metrics-report.yml`, `notify-slack.yml` (functionality moved to composite
action), `preflight.yml`, `static-analysis-gate.yml`, `tag-release.yml`
(absorbed into `cd-core.yml`), `test-gate.yml`.

`ci-cd-core.yml` → renamed to `cicd-orchestrator.yml`. A stub at the old
path exists for one week after merge; then removed.

**If you think you need an exception:** you don't. If a caller genuinely has
a special need, express it as a composite action under `actions/`, not a new
top-level workflow. Ask the repo owner before deviating.

**Directive for future agents:** `~/.claude/directives/cicd.md`.

---

## 2026-04-21 — Caller repos run ONE workflow file.

**Decision:** Every repo in the `sonarmd/` org that uses this orchestrator
has exactly one file in its `.github/workflows/` directory, named `ci.yml`,
looking nearly identical across repos. The only variation: the `setup` and
`steps` YAML block bodies.

**Canonical wrapper:** see `~/.claude/directives/cicd.md`.

**Affected repos** (Phase 2 of `cicd-unification` plan):
- `triggr_api`
- `infra-cdk`
- `frontend-patient-app`
- `frontend` (includes CircleCI removal)
- `triggr_misc` mobile (includes CircleCI removal)

Mobile app calls EAS from Ansible, not from GHA. GHA only runs a local
sanity build as part of CI `steps`.

---

## 2026-04-21 — `deploy.json` contract is validated at the edge, once.

**Decision:** Every caller repo includes a `deploy.json` at the repo root
conforming to the schema defined by `sonarmd/workflows`. The CI step bundles
it into the release artifact. Ansible consumes it to drive the deploy.

**`deploy.json` is NOT validated** by `ci-core.yml`, `cd-core.yml`, or
`cicd-orchestrator.yml`. Validation happens once, at the edge (the
bundling step, or hubot/Ansible when it picks up the release). Repeated
validation = repeated work = violates the "no repeated work" rule.

---

## 2026-04-21 — GitHub does not access AWS. Ansible does.

**Decision:** GitHub Actions workflows never assume AWS IAM roles. No OIDC
federation from GHA to AWS. GitHub's job is to build, sign, tag, publish
the release, and notify Slack. That is the extent of GitHub's authority.

Ansible (on the Ansible server, using its own IAM role scoped to the server)
picks up the Slack signal via hubot and performs the actual AWS operations:
- Frontend: `aws s3 sync` per app per env
- API: EC2 deploy + secrets drop + Lambda zips to CDK bucket
- CDK: synth JSON → S3 → trigger CloudFormation
- Mobile: call EAS with the git tag

`infra-cdk/GithubOidcStack` exists for historical reasons or for a different
purpose; it is not consumed by this architecture and should not be wired in.

---

## 2026-05-23 — Agent Architecture Review lives outside the CI/CD core.

**Decision:** A new top-level reusable workflow,
`.github/workflows/agent-architecture-review.yml`, runs an agent-based
ARCHITECTURE reviewer on every PR. It is **not** part of the CI/CD core
(`ci-core`, `cd-core`, `cicd-orchestrator`).

**Rationale:** The "three workflows only" rule scopes specifically to CI/CD
orchestration. Architecture review is an orthogonal concern — it does not
gate the build, sign the release, or drive deploy. It produces advisory
output (comments, labels, a check run). Same pattern as
`auto-safety-tag.yml`, which also lives outside the CI/CD core and is
called by repos as a thin separate workflow.

**Default purpose: architecture, not generic code review.** The default
rubric evaluates naming, domain boundaries, separation of concerns,
dependency direction, abstraction leakage, small/clean code, maintainability,
coupling, and fit with existing project patterns. `senior-eye` is the
default overlay. `security` and `hipaa-soc2` are opt-in overlays, not
always-on defaults.

**Two-stage architecture with a HARD security boundary:**

| Stage | Container | Permissions | Secrets | Capability |
|---|---|---|---|---|
| `prepare` | ubuntu | read-only | none | Fetches PR diff + metadata via API |
| `review-agent` | `ghcr.io/sonarmd/agent-reviewer` | NONE (`permissions: {}`) | `ANTHROPIC_API_KEY` only | Runs LLM. No `gh` CLI. No GITHUB_TOKEN. |
| `publish` | ubuntu | pr/issue/check: write | GITHUB_TOKEN only | Validates findings, posts comments/labels/check |

The LLM is **fundamentally incapable** of writing to GitHub. The publisher
only acts on findings that pass schema + diff-position validation. Inline
comments only land at `(file, line)` positions verified against the diff
that the publisher RE-FETCHES via API.

**Shape:**
- Reusable workflow: `.github/workflows/agent-architecture-review.yml` (workflow_call, 3 jobs).
- Top-level wrapper: `.github/workflows/agent-architecture-review-default.yml`
  is what org admins register as a required workflow for zero-caller adoption.
- Container image: `ghcr.io/sonarmd/agent-reviewer` (public, no secrets,
  no `gh` CLI in image). Built by `.github/workflows/build-agent-reviewer-image.yml`.
- Composite actions: `agent-arch-review-{agent,publish,config}`.
- Schema: `schemas/agent-review-findings.v2.schema.json` (v2, versioned).
- Per-repo override: optional `.github/agent-review.yml` in consumer repo.
- Caller template: `per-repo/_template/.github/workflows/agent-architecture-review.yml`.

**Rollout — pick one:**
- **Path A (preferred):** org admin registers the default wrapper as a
  required workflow + sets `ANTHROPIC_API_KEY` as an org-level secret.
  Zero per-repo effort. Per-repo tuning via `.github/agent-review.yml`.
- **Path B (fallback):** `scripts/bootstrap-agent-review.sh` opens a
  DRAFT PR per repo adding the thin caller template.

**Auth:** primary is `CLAUDE_CODE_OAUTH_TOKEN` (Claude Code subscription
billing — generated by `claude setup-token`). `ANTHROPIC_API_KEY` is
accepted as a fallback if a caller prefers per-token billing. The image
detects which is set; OAuth token wins if both are present. Either secret
is exposed ONLY to the `review-agent` job; the publisher never sees them.

**Fork safety:** trigger is `pull_request_target`. PR code is NEVER
checked out as executable by default. The diff is fetched via API and
treated as DATA. `allow_pr_head_checkout` is an explicit opt-in for
read-only context (still no package manager invocation).

**Failure behavior:** advisory by default. Malformed LLM output → neutral
check + "review unavailable" comment + exit 0. A bad model day never
blocks the org, even in `required` enforcement mode.

**Privacy:** The PR diff is sent to Anthropic's API. Repos that commit
raw PHI in fixtures or migrations must NOT enable this workflow until a
redaction pre-filter ships (v2).

**Not a substitute for `ci-core`.** Reviewer findings are advisory. Tests,
lint, and build still gate via `ci-core` + `gate.yml`.

**Directive for future agents:** `docs/agent-architecture-review.md`.
Design rationale: `.claude/plans/agent-architecture-review.md`.
