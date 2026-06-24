// Publish orchestrator: gate -> render -> create-or-update -> backlink.
// Reads authored pages (from the doc-author stage) and the existing-corpus title set
// (from doc-author-prepare), publishes each page to Confluence, and back-links the
// related existing pages to it. Per-page failures are isolated and logged; one bad page
// never aborts the run and never fails the deploy. Honors DRY_RUN for local testing.
//
// Inputs (argv or env):
//   --authored <authored.json>   { pages: [ { slug,title,parent,labels[],markdown,backlinks[] } ] }
//   --corpus   <corpus.json>     { titles: [..], slugToTitle: {..}, glossaryTitle }  (optional)
// Env:
//   CONFLUENCE_BASE_URL, CONFLUENCE_USER, CONFLUENCE_TOKEN, CONFLUENCE_SPACE
//   CONFLUENCE_PARENT_ID   fallback parent page id when a page's parent title is unknown
//   DRY_RUN=1              no network; log intended mutations

const fs = require('fs');
const { toStorage, makeResolver } = require('./render');
const { scan } = require('./gate');
const { Confluence } = require('./confluence');

function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

function loadJson(p, dflt) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return dflt; }
}

async function main() {
  const authored = loadJson(arg('--authored', 'authored.json'), { pages: [] });
  const corpus = loadJson(arg('--corpus', 'corpus.json'), { titles: [], slugToTitle: {}, glossaryTitle: 'Glossary' });

  const dryRun = process.env.DRY_RUN === '1' || !process.env.CONFLUENCE_TOKEN;
  const spaceKey = process.env.CONFLUENCE_SPACE || 'SE';

  // resolver lets authored {page="..."} refs point at existing corpus pages + new pages
  const titleSet = new Set([...(corpus.titles || []), ...authored.pages.map((p) => p.title)]);
  const slugToTitle = corpus.slugToTitle || {};
  const resolver = makeResolver(titleSet, slugToTitle, corpus.glossaryTitle || 'Glossary', spaceKey);

  const conf = new Confluence({
    baseUrl: process.env.CONFLUENCE_BASE_URL,
    user: process.env.CONFLUENCE_USER,
    token: process.env.CONFLUENCE_TOKEN,
    spaceKey, dryRun,
  });

  const results = [];
  for (const page of authored.pages) {
    const r = { slug: page.slug, title: page.title };
    try {
      const g = scan(page.markdown || '');
      if (!g.ok) {
        r.status = 'skipped-gate';
        r.violations = g.violations;
        console.log(`SKIP "${page.title}": gate failed - ${g.violations.map((v) => `${v.kind}:${v.detail}`).join(', ')}`);
        results.push(r);
        continue;
      }
      const storage = toStorage(page.markdown, resolver);
      let parentId = process.env.CONFLUENCE_PARENT_ID || null;
      if (page.parent) {
        const parent = await conf.findByTitle(page.parent);
        if (parent) parentId = parent.id;
      }
      const up = await conf.upsert({ title: page.title, storage, parentId, labels: page.labels || [] });
      r.status = up.action; // create | update
      r.pageId = up.id;

      r.backlinks = [];
      for (const fromTitle of page.backlinks || []) {
        const bl = await conf.backlink(fromTitle, page.title);
        r.backlinks.push({ from: fromTitle, action: bl.action });
      }
      console.log(`${up.action.toUpperCase()} "${page.title}" [${up.id}] backlinks:${(page.backlinks || []).length}`);
    } catch (err) {
      r.status = 'error';
      r.error = err.message;
      console.log(`ERROR "${page.title}": ${err.message}`);
    }
    results.push(r);
  }

  const summary = {
    dryRun,
    space: spaceKey,
    total: results.length,
    created: results.filter((r) => r.status === 'create').length,
    updated: results.filter((r) => r.status === 'update').length,
    skipped: results.filter((r) => r.status === 'skipped-gate').length,
    errored: results.filter((r) => r.status === 'error').length,
    results,
  };
  fs.writeFileSync('publish-result.json', JSON.stringify(summary, null, 2) + '\n');
  console.log(`\npublish: ${summary.created} created, ${summary.updated} updated, ` +
    `${summary.skipped} gate-skipped, ${summary.errored} errored (dry-run=${dryRun})`);
}

main().catch((err) => { console.error(err.message); process.exit(1); });
