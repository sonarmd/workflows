# doc-author action set

Automated documentation authoring for the deploy path. A sibling of the
`agent-arch-review-*` pattern: same prepare -> agent -> publish skeleton, but it authors
catalog docs from what shipped instead of reviewing a PR diff. Built to run as a
NON-BLOCKING parallel job alongside CD on merges to `main`/`release` (wiring deferred).

## The three stages

1. **doc-author-prepare** (plain runner, read-only, no LLM)
   Gathers grounding evidence: changed files + commit subjects since the baseline ref,
   the `.agent/` records added for the work, and the existing docs corpus (titles +
   excerpts). Emits `change.json`, `corpus.json`, `grounding.md`.

2. **doc-author** (plain runner, Anthropic API only)
   Claude reads the grounding + corpus and authors/updates the warranted pages. Emits
   `authored.json` = `{ pages: [ { slug, title, parent, labels[], markdown, backlinks[] } ] }`.
   Non-blocking: no key or any error -> empty page set, exit 0.

3. **doc-author-publish** (plain runner, scoped, no LLM)
   For each page: safety gate (ASCII + secret + PHI) -> render markdown to Confluence
   storage -> create-or-update by title (idempotent) -> labels/parent -> back-link
   related existing pages. A gate failure skips the page; never uploads, never fails the
   deploy. Hard 5-minute cap. Dry-run when no Confluence credentials are present.

## Threat model (why simpler than agent-arch-review)

agent-arch-review hardens against untrusted PR code from forks, so its agent runs in a
locked-down container with zero GitHub scopes. doc-author runs AFTER merge on
`main`/`release` - trusted code, our own corpus - so the author stage is a plain-runner
script. The publish gate is still the hard backstop against anything the model emits.

## Auth (injected upstream, never stored here)

- `ANTHROPIC_API_KEY` -> doc-author input.
- `CONFLUENCE_USER` / `CONFLUENCE_TOKEN` (+ optional `CONFLUENCE_BASE_URL`) in the env for
  doc-author-publish. Both come from 1Password via the load-secrets action in CI.

## Local testing (no network)

```
node doc-author-prepare/scripts/prepare.js --repo <caller> --corpus-dir <docs> --out work
node doc-author/scripts/author.js --grounding work/grounding.md --corpus work/corpus.json --out work/authored.json --offline
DRY_RUN=1 node doc-author-publish/lib/publish.js --authored work/authored.json --corpus work/corpus.json
```

## Deferred

- Wire the non-blocking parallel job into `cicd-orchestrator.yml` (separate PR, owner go).
- 1Password `smd_cicd`: Confluence + Anthropic secrets via load-secrets.
- Live end-to-end run on a real deploy.
