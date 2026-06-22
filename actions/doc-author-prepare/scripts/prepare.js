// doc-author-prepare: gather the grounding evidence the author stage needs, with NO LLM
// access. Produces three artifacts:
//   change.json    what shipped: changed files + commit subjects since the baseline ref
//   corpus.json    the existing docs corpus: titles + slug->title + glossary title
//   grounding.md   a human/agent-readable digest combining the above + .agent/ records
//
// Inputs (argv):
//   --repo <dir>        caller checkout (default: cwd)
//   --since <ref>       baseline git ref to diff from (default: last tag, else HEAD~50)
//   --corpus-dir <dir>  dir of existing doc markdown (<slug>.md + <slug>.meta.json)
//   --out <dir>         output dir (default: work/)
// Side-effect-free except writing into --out. Never throws fatally; missing inputs degrade.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

function arg(name, dflt) {
  const i = process.argv.indexOf(name);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : dflt;
}

function sh(cmd, cwd) {
  try { return execSync(cmd, { cwd, maxBuffer: 64 * 1024 * 1024 }).toString().trim(); }
  catch { return ''; }
}

function baselineRef(repo, since) {
  if (since) return since;
  const lastTag = sh('git describe --tags --abbrev=0', repo);
  if (lastTag) return lastTag;
  return 'HEAD~50';
}

function gatherChange(repo, since) {
  const base = baselineRef(repo, since);
  const range = `${base}..HEAD`;
  const files = sh(`git diff --name-status ${range}`, repo).split('\n').filter(Boolean)
    .map((l) => { const [status, ...rest] = l.split('\t'); return { status, path: rest.join('\t') }; });
  const commits = sh(`git log --format=%s ${range}`, repo).split('\n').filter(Boolean);
  const diffstat = sh(`git diff --stat ${range}`, repo);
  return { baseline: base, range, files, commits, diffstat };
}

// .agent/ records added or modified in the range (plans, decisions, incidents).
function gatherAgentRecords(repo, change) {
  const recs = [];
  for (const f of change.files) {
    if (!f.path.startsWith('.agent/')) continue;
    if (f.status === 'D') continue;
    const abs = path.join(repo, f.path);
    if (!fs.existsSync(abs)) continue;
    recs.push({ path: f.path, body: fs.readFileSync(abs, 'utf8').slice(0, 8000) });
  }
  return recs;
}

function gatherCorpus(corpusDir) {
  const out = { titles: [], slugToTitle: {}, glossaryTitle: 'Glossary', pages: [] };
  if (!corpusDir || !fs.existsSync(corpusDir)) return out;
  for (const f of fs.readdirSync(corpusDir)) {
    if (!f.endsWith('.md')) continue;
    const slug = f.replace(/\.md$/, '');
    const metaPath = path.join(corpusDir, slug + '.meta.json');
    const meta = fs.existsSync(metaPath) ? JSON.parse(fs.readFileSync(metaPath, 'utf8')) : { title: slug };
    out.titles.push(meta.title);
    out.slugToTitle[slug] = meta.title;
    if (/glossary/.test(slug)) out.glossaryTitle = meta.title;
    // a short excerpt gives the author style + cross-link targets without the full corpus
    const body = fs.readFileSync(path.join(corpusDir, f), 'utf8');
    out.pages.push({ slug, title: meta.title, parent: meta.parent || null, excerpt: body.slice(0, 1200) });
  }
  return out;
}

function grounding(change, agentRecords, corpus) {
  const L = [];
  L.push('# Doc authoring grounding context', '');
  L.push(`Baseline: ${change.baseline}  (range ${change.range})`, '');
  L.push('## What shipped', '');
  L.push('Commits:'); for (const c of change.commits.slice(0, 60)) L.push(`- ${c}`);
  L.push('', 'Changed files:');
  for (const f of change.files.slice(0, 200)) L.push(`- ${f.status} ${f.path}`);
  L.push('', '## Accumulated .agent/ records for this work', '');
  if (!agentRecords.length) L.push('(none in range)');
  for (const r of agentRecords) { L.push(`### ${r.path}`, '', r.body, ''); }
  L.push('## Existing documentation corpus (titles + excerpts)', '');
  for (const p of corpus.pages) {
    L.push(`### ${p.title}${p.parent ? ` (under ${p.parent})` : ''}`, '', p.excerpt.replace(/\s+$/, ''), '');
  }
  return L.join('\n');
}

function main() {
  const repo = arg('--repo', process.cwd());
  const since = arg('--since', '');
  const corpusDir = arg('--corpus-dir', '');
  const out = arg('--out', 'work');
  fs.mkdirSync(out, { recursive: true });

  const change = gatherChange(repo, since);
  const agentRecords = gatherAgentRecords(repo, change);
  const corpus = gatherCorpus(corpusDir);

  fs.writeFileSync(path.join(out, 'change.json'), JSON.stringify(change, null, 2) + '\n');
  fs.writeFileSync(path.join(out, 'corpus.json'),
    JSON.stringify({ titles: corpus.titles, slugToTitle: corpus.slugToTitle, glossaryTitle: corpus.glossaryTitle, pages: corpus.pages }, null, 2) + '\n');
  fs.writeFileSync(path.join(out, 'grounding.md'), grounding(change, agentRecords, corpus));

  console.log(`prepare: ${change.files.length} changed files, ${change.commits.length} commits, ` +
    `${agentRecords.length} agent records, ${corpus.pages.length} corpus pages -> ${out}/`);
}

main();
