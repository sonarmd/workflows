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
