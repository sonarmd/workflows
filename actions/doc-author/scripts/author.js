// doc-author: the LLM stage. Reads the grounding context + corpus from doc-author-prepare
// and asks Claude to author or update the documentation pages warranted by what shipped.
// Output: authored.json { pages: [ { slug,title,parent,labels[],markdown,backlinks[] } ] }.
//
// Non-blocking by contract: if no API key is present, or the model returns nothing usable,
// it writes an empty page set and exits 0 (the publish stage then no-ops). The model is
// instructed to emit ASCII-only, PHI-free markdown; the publish gate is the backstop.
//
// Inputs (argv): --grounding <grounding.md> --corpus <corpus.json> --out <authored.json>
//                --model <id> [--offline]
// Env: ANTHROPIC_API_KEY

const fs = require('fs');

function arg(name, dflt) {
  const i = process.argv.indexOf(name);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : dflt;
}
const has = (name) => process.argv.includes(name);

const SYSTEM = [
  'You are a staff engineer maintaining a living system-documentation catalog in Confluence.',
  'You are given (a) what shipped in a feature (commits, changed files, accumulated .agent/',
  'records) and (b) the existing documentation corpus (page titles, parents, excerpts).',
  'Decide which catalog pages must be created or updated to reflect what shipped. Author the',
  'full markdown for each. Rules:',
  '- ASCII only. No smart quotes, em dashes, arrows, or any non-ASCII character.',
  '- PHI-free. Never include patient data, names, SSNs, MRNs. Team-role names only.',
  '- No secrets, tokens, keys, or credentials.',
  '- Match the style and section structure of the corpus excerpts.',
  '- Link to related existing pages with {page="Exact Title"} and glossary terms with',
  '  [text](glossary#anchor).',
  '- Prefer updating an existing page (reuse its exact title) over creating a near-duplicate.',
  '- For each authored page, list backlinks: titles of existing pages that should point to it.',
  'Return STRICT JSON only, no prose, shaped as:',
  '{"pages":[{"slug":"kebab","title":"Exact Title","parent":"Parent Title",',
  '"labels":["system-page"],"markdown":"# ...","backlinks":["Other Title"]}]}',
].join('\n');

async function callClaude(model, grounding, corpus) {
  const userParts = [
    'EXISTING CORPUS TITLES (link targets / pages you may update):',
    JSON.stringify({ titles: corpus.titles, slugToTitle: corpus.slugToTitle }, null, 0),
    '',
    'GROUNDING (what shipped + .agent records + corpus excerpts):',
    grounding,
    '',
    'Author the pages now. Return strict JSON only.',
  ].join('\n');

  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': process.env.ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model,
      max_tokens: 16000,
      system: SYSTEM,
      messages: [{ role: 'user', content: userParts }],
    }),
  });
  if (!res.ok) throw new Error(`anthropic ${res.status}: ${(await res.text()).slice(0, 300)}`);
  const data = await res.json();
  const text = (data.content || []).filter((b) => b.type === 'text').map((b) => b.text).join('');
  return text;
}

// Pull the first balanced JSON object out of the model text.
function extractJson(text) {
  const start = text.indexOf('{');
  if (start < 0) return null;
  let depth = 0, inStr = false, esc = false;
  for (let i = start; i < text.length; i++) {
    const c = text[i];
    if (inStr) { if (esc) esc = false; else if (c === '\\') esc = true; else if (c === '"') inStr = false; continue; }
    if (c === '"') inStr = true;
    else if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return text.slice(start, i + 1); }
  }
  return null;
}

function offlineFixture(corpus) {
  // deterministic stand-in for wiring tests: a single update to the first corpus page
  const first = (corpus.pages && corpus.pages[0]) || { slug: 'example', title: 'Example', parent: null };
  return { pages: [{
    slug: first.slug, title: first.title, parent: first.parent || 'System Catalog',
    labels: ['system-page'],
    markdown: `# ${first.title}\n\n(Offline fixture: doc-author wiring test, no model call.)\n`,
    backlinks: [],
  }] };
}

async function main() {
  const groundingPath = arg('--grounding', 'work/grounding.md');
  const corpusPath = arg('--corpus', 'work/corpus.json');
  const out = arg('--out', 'work/authored.json');
  const model = arg('--model', 'claude-opus-4-8');

  const grounding = fs.existsSync(groundingPath) ? fs.readFileSync(groundingPath, 'utf8') : '';
  const corpus = fs.existsSync(corpusPath) ? JSON.parse(fs.readFileSync(corpusPath, 'utf8')) : { titles: [], pages: [] };

  let authored = { pages: [] };
  if (has('--offline')) {
    authored = offlineFixture(corpus);
    console.log('doc-author: offline fixture (no model call)');
  } else if (!process.env.ANTHROPIC_API_KEY) {
    console.log('doc-author: no ANTHROPIC_API_KEY - writing empty page set (non-blocking)');
  } else {
    try {
      const raw = await callClaude(model, grounding, corpus);
      const json = extractJson(raw);
      authored = json ? JSON.parse(json) : { pages: [] };
      if (!Array.isArray(authored.pages)) authored = { pages: [] };
      console.log(`doc-author: model proposed ${authored.pages.length} page(s)`);
    } catch (err) {
      console.log(`doc-author: model call failed (non-blocking): ${err.message}`);
      authored = { pages: [] };
    }
  }
  fs.writeFileSync(out, JSON.stringify(authored, null, 2) + '\n');
}

main().catch((err) => { console.error(err.message); process.exit(0); }); // never block the deploy
