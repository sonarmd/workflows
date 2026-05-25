# Agent Architecture Review

A reusable GitHub workflow that runs an **architecture-focused** agent
reviewer over every PR diff. Language-agnostic, framework-agnostic,
zero-effort per repo via the org-level required-workflow path.

The reviewer evaluates: naming, domain boundaries, separation of concerns,
dependency direction, abstraction leakage, small/clean code, maintainability,
coupling, and whether the PR fits existing project patterns. Optional
overlays add senior-eye, security, and HIPAA/SOC2 lenses.

## Adoption — pick one path

### Path A — Org-level required workflow (zero per-repo effort)

For org admins. Reviews every PR in the org's scoped repos automatically.

1. **Settings → Actions → Secrets**: add `CLAUDE_CODE_OAUTH_TOKEN` as an
   organization secret (preferred — uses your Claude Code subscription,
   not per-token API billing). Generate it locally with `claude setup-token`
   while signed in to the subscription account you want to bill against.
   Scope to the repos that should run the reviewer.
   _(Or `ANTHROPIC_API_KEY` for per-token billing.)_
2. **Settings → Actions → General → Required workflows**:
   - Add workflow → source repo: `sonarmd/workflows`
   - Path: `.github/workflows/agent-architecture-review-default.yml`
   - Ref: `main`
   - Scope to selected repositories.
3. Done. Every PR in scope runs the reviewer with defaults.

To tune per-repo: drop `.github/agent-review.yml` in the repo (see
[template](../per-repo/_template/.github/agent-review.yml)).

### Path B — Bootstrap PR per repo (fallback)

For repos not covered by Path A. Opens a DRAFT PR adding the thin caller
template.

```bash
scripts/bootstrap-agent-review.sh sonarmd/triggr_api sonarmd/frontend
# or
scripts/bootstrap-agent-review.sh --from-file repos.txt
```

The script is idempotent — repeated runs skip repos that already adopted.

### Minimal caller example (Path B)

```yaml
# .github/workflows/agent-architecture-review.yml
name: Agent Architecture Review
on:
  pull_request_target:
    types: [opened, synchronize, reopened]
permissions:
  contents: read
  pull-requests: write
  issues: write
  checks: write
  packages: read
jobs:
  review:
    uses: sonarmd/workflows/.github/workflows/agent-architecture-review.yml@main
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
      # ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}  # only if you prefer per-token billing
```

## How it works

The reusable workflow runs three jobs in sequence with a **hard
agent→publisher security boundary**:

```
prepare → review-agent → publish
─────────────────────────────────
ubuntu     container      ubuntu
read-only  NO GH access   pr/issue/check: write
fetch diff run LLM        validate + post
upload     emit findings  schema + diff-position validation
artifact   artifact       comments + labels + check
```

| Stage | What it can do | What it can NOT do |
|---|---|---|
| **prepare** | Read PR metadata + diff via API | Write to GitHub. Run PR code. |
| **review-agent** | Call Anthropic API with the diff | Write to GitHub (no token at all). Run gh CLI (not installed). Execute PR code (no checkout). |
| **publish** | Post comments, labels, check run | Call the LLM. Apply labels outside `agent-review/*` prefix. Post inline comments at positions not in the diff. |

The LLM cannot cause arbitrary GitHub writes — every action the publisher
takes is constrained to validated findings and the `agent-review/*` label
prefix.

## Lenses

Composed into a SINGLE agent call (one Anthropic API request per PR).

| Mode / Overlay | Default? | Purpose |
|---|---|---|
| **architecture** (default mode) | ✅ | Naming, boundaries, separation, dependency direction, abstraction, small clean code, maintainability, coupling, pattern fit. Caps at `medium` severity. |
| **senior-eye** (default overlay) | ✅ | Blast radius, missing tests for changed behavior, things juniors miss. |
| **security** (opt-in overlay or mode) | | Injection, auth, secret leaks, SSRF/XSS, IAM scope. |
| **hipaa-soc2** (opt-in overlay or mode) | | PHI in logs, audit-log coverage, encryption, BAA scope. |

Set `review_mode: security` or `review_mode: compliance` to make those the
primary rubric instead of an overlay.

## Inputs

All optional. Can be set on the caller workflow's `with:` block OR in
`.github/agent-review.yml` (per-repo config takes precedence).

| Input | Default | Description |
|---|---|---|
| `review_mode` | `architecture` | `architecture` / `architecture+senior` / `security` / `compliance` / `custom` |
| `overlays` | `senior-eye` | Comma-list of overlays |
| `enforcement_mode` | `advisory` | `advisory` (success always) / `soft-fail` (neutral on findings) / `required` (failure on findings) |
| `severity_threshold` | `medium` | Minimum severity to surface |
| `fail_threshold` | `high` | Severities ≥ this flip check red (in `required` mode) |
| `max_inline_comments` | `20` | Cap inline comments to avoid spam |
| `include_paths` | `""` | Newline-separated globs |
| `exclude_paths` | `""` | Newline-separated globs |
| `post_summary_comment` | `true` | Post one summary comment per PR |
| `post_inline_comments` | `true` | Post inline review comments |
| `apply_labels` | `true` | Apply `agent-review/*` labels |
| `allow_pr_head_checkout` | `false` | Security: opt-in to checking out PR head for richer context (still no code execution) |
| `check_name` | `Agent Architecture Review` | Display name of the check run |
| `image_tag` | `:latest` | Override the GHCR tag (testing) |

## Secrets

| Secret | Required | Notes |
|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | one of these | Claude Code subscription OAuth token. Subscription billing. Get with `claude setup-token`. **Preferred.** |
| `ANTHROPIC_API_KEY` | one of these | Anthropic API key. Per-token billing. Fallback if you don't want subscription auth. |

At least one of the two must be set. If both are set, the OAuth token takes
precedence (subscription billing wins). Only the agent job sees these
secrets; the publisher job never receives them.

## Security model

### Trigger choice

`pull_request_target` is the trigger. This is what lets secrets and the
write token flow on PRs (including forks). Without it, fork PRs can't
be reviewed because secrets are blocked on `pull_request`.

`pull_request_target` runs the workflow from the **base branch**, not
the PR branch. That means changes to this workflow in a PR don't take
effect until merge — a feature, not a bug. The reusable workflow itself
lives in `sonarmd/workflows` and is invoked `@main`; consumers always
get the merged version.

### No PR code execution

The workflow does NOT check out PR head as code by default. The diff is
fetched via the GitHub API (`gh api repos/{}/{}/pulls/{}` with the
`vnd.github.v3.diff` accept header) and treated as data. No package
manager runs against PR code. No build steps execute PR code.

If a use case needs related-file context, set
`allow_pr_head_checkout: true` — this enables a **read-only** checkout
of PR head. No `npm install`, no `pip install`, no execution.

### LLM has no GitHub access

The `review-agent` job declares `permissions: {}` — no GITHUB_TOKEN is
provisioned. The container image deliberately has NO `gh` CLI. The agent
gets the PR diff as a file and outputs to stdout/an artifact. It has no
network path to GitHub.

Even if the LLM were prompt-injected by malicious diff content, it
cannot make GitHub API calls. The worst it can do is emit garbage
findings, which the publisher then refuses to post (schema validation
+ diff-position validation).

### Findings must map to diff positions

Every inline comment is anchored to a `(file, line)` that the publisher
re-verifies against the PR's actual diff (re-fetched via API). Findings
whose positions don't map are dropped (count surfaced in the summary
comment). The LLM cannot make the publisher post a comment on a file
or line that isn't in the diff.

### Label discipline

The publisher only manages labels under the `agent-review/` prefix. It
will create labels missing from the repo (with bot-managed description)
and remove stale ones from prior runs. It will NEVER touch a label
outside `agent-review/*`.

### Failure behavior — never blocks the org on a bad model day

| Failure | Behavior |
|---|---|
| LLM API call fails | Findings file emitted with `parser_status: "malformed"`. Check `neutral`. Comment says "review unavailable". Workflow exits 0. |
| LLM returns non-JSON | Same as above. |
| Schema validation fails | Same as above. |
| Findings reference non-existent lines | Those findings dropped, count logged. Remaining valid findings posted normally. |
| Image pull fails | Job fails (standard GHA failure). No check posted (nothing to publish). |

The "required" enforcement mode only fails the check when the agent
produced parseable findings AND those findings meet the fail_threshold.
A malformed agent run never trips required mode.

## Schema

The contract between Stage 1 and Stage 2:
[`schemas/agent-review-findings.v2.schema.json`](../schemas/agent-review-findings.v2.schema.json).

Versioned (`schema_version: "2"`). The publisher refuses to act on any
other version.

## File layout

```
sonarmd/workflows/
├── .github/workflows/
│   ├── agent-architecture-review.yml          ← reusable workflow (workflow_call)
│   ├── agent-architecture-review-default.yml  ← top-level wrapper for required-workflow path
│   └── build-agent-reviewer-image.yml         ← builds the container
├── actions/
│   ├── agent-arch-review-agent/               ← Stage 1: run agent
│   ├── agent-arch-review-publish/             ← Stage 2: validate + post
│   └── agent-arch-review-config/              ← merge per-repo config
├── docker/agent-reviewer/
│   ├── Dockerfile                              ← image source
│   ├── entrypoint.sh                          ← Stage 1 binary
│   ├── rubrics/                                ← architecture + overlays
│   └── schemas/findings.v2.schema.json
├── per-repo/_template/
│   ├── .github/workflows/agent-architecture-review.yml   ← Path B caller template
│   └── .github/agent-review.yml                          ← per-repo config template
├── schemas/agent-review-findings.v2.schema.json          ← public schema
└── scripts/bootstrap-agent-review.sh                     ← Path B opener
```

## Versioning the image

The container image is rebuilt by
[`build-agent-reviewer-image.yml`](../.github/workflows/build-agent-reviewer-image.yml)
on every change to `docker/agent-reviewer/**` and on a weekly cron.

Tags:
- `:latest` — most recent main build (what the reusable workflow uses by default)
- `:sha-<12hex>` — pinned by commit
- `:weekly-YYYY-MM-DD` — only on cron, for audit

Pin via the `image_tag` input if you want stability across image rebuilds:

```yaml
with:
  image_tag: ghcr.io/sonarmd/agent-reviewer:sha-abc123def456
```

## Privacy / PHI

The PR diff is sent to the Anthropic API. **Do not enable this workflow
on repos that commit raw PHI in fixtures or migrations.** A future
version will include a redaction pre-filter; for now, the constraint is
editorial.

## See also

- [`auto-safety-tag.yml`](../.github/workflows/auto-safety-tag.yml) — same caller pattern.
- [`DECISIONS.md`](../DECISIONS.md) — why this lives outside the CI/CD core.
- [`.claude/plans/agent-architecture-review.md`](../.claude/plans/agent-architecture-review.md) — design plan.
