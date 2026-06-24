// Render authored markdown -> Confluence storage XHTML. Ported from the docs-pipeline
// converter (pandoc-based, lossless). Input is a directory of authored pages
// (<slug>.md + <slug>.meta.json) plus the existing-corpus title set used to resolve
// cross-links. Re-runnable and side-effect-free. Requires pandoc on PATH. ASCII only.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const b64url = (s) => Buffer.from(s, 'utf8').toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64url = (s) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
const xmlEsc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

const JUNK_TARGETS = new Set(['Term Name', 'System Name', 'Title', 'Page Title', 'X', 'term', 'anchor']);

// titleSet/slugToTitle resolve {page="..."} refs; glossary anchor links go to glossaryTitle.
function makeResolver(titleSet, slugToTitle, glossaryTitle, spaceKey) {
  const resolve = (raw) => {
    if (titleSet.has(raw)) return { title: raw, internal: true };
    if (slugToTitle[raw]) return { title: slugToTitle[raw], internal: true };
    return { title: raw, internal: false };
  };
  const acLinkPage = (targetRaw, text) => {
    if (JUNK_TARGETS.has(targetRaw)) return text;
    const { title, internal } = resolve(targetRaw);
    const ri = internal
      ? `<ri:page ri:content-title="${xmlEsc(title)}" />`
      : `<ri:page ri:content-title="${xmlEsc(title)}" ri:space-key="${spaceKey}" />`;
    return `<ac:link>${ri}<ac:plain-text-link-body><![CDATA[${text}]]></ac:plain-text-link-body></ac:link>`;
  };
  const acLinkAnchor = (anchor, text) =>
    `<ac:link ac:anchor="${xmlEsc(anchor)}"><ri:page ri:content-title="${xmlEsc(glossaryTitle)}" /><ac:plain-text-link-body><![CDATA[${text}]]></ac:plain-text-link-body></ac:link>`;
  return { acLinkPage, acLinkAnchor };
}

const codeMacro = (lang, body) =>
  `<ac:structured-macro ac:name="code"><ac:parameter ac:name="language">${lang}</ac:parameter><ac:plain-text-body><![CDATA[${body}]]></ac:plain-text-body></ac:structured-macro>`;

// Markdown string -> Confluence storage XHTML.
function toStorage(md, resolver) {
  // 1. protect code from placeholder rewriting
  const blocks = [];
  md = md.replace(/```(\w*)[ \t]*\n([\s\S]*?)```/g, (_, lang, body) => {
    blocks.push({ lang: lang || 'text', body: body.replace(/\s+$/, '') });
    return `\n\n@@CODE${blocks.length - 1}@@\n\n`;
  });
  const inlines = [];
  md = md.replace(/`([^`\n]+)`/g, (_, body) => { inlines.push(body); return `@@IC${inlines.length - 1}@@`; });

  // 2. page/glossary refs -> sentinel links that survive pandoc
  md = md.replace(/\[([^\]]+)\]\{page="glossary#([^"]+)"\}/g, (_, x, a) => `[${x}](https://conf.local/g/${b64url(a)})`);
  md = md.replace(/\{page="glossary#([^"]+)"\}/g, (_, a) => `[${a.replace(/-/g, ' ')}](https://conf.local/g/${b64url(a)})`);
  md = md.replace(/\[([^\]]+)\]\{page="([^"]+)"\}/g, (_, x, p) => `[${x}](https://conf.local/p/${b64url(p)})`);
  md = md.replace(/\{page="([^"]+)"\}/g, (_, p) => `[${p}](https://conf.local/p/${b64url(p)})`);
  md = md.replace(/\[([^\]]+)\]\(glossary#([a-z0-9._-]+)\)/g, (_, x, a) => `[${x}](https://conf.local/g/${b64url(a)})`);

  // 3. pandoc gfm -> html5
  let html = execSync('pandoc -f gfm+raw_html -t html5-auto_identifiers --wrap=none', { input: md, maxBuffer: 64 * 1024 * 1024 }).toString();
  html = html.replace(/\s(?:id|class|style|data-[\w-]+)="[^"]*"/g, '').replace(/<\/?div[^>]*>/g, '');

  // 3b. restore protected code
  html = html.replace(/<p>\s*@@CODE(\d+)@@\s*<\/p>/g, (_, i) => codeMacro(blocks[+i].lang === 'mermaid' ? 'mermaid' : blocks[+i].lang, blocks[+i].body));
  html = html.replace(/@@CODE(\d+)@@/g, (_, i) => codeMacro(blocks[+i].lang === 'mermaid' ? 'mermaid' : blocks[+i].lang, blocks[+i].body));
  html = html.replace(/@@IC(\d+)@@/g, (_, i) => `<code>${xmlEsc(inlines[+i])}</code>`);

  // 4. sentinel links -> Confluence ac:link macros
  html = html.replace(/<a href="https:\/\/conf\.local\/p\/([A-Za-z0-9_-]+)"[^>]*>([\s\S]*?)<\/a>/g,
    (_, enc, text) => resolver.acLinkPage(unb64url(enc), text.replace(/<[^>]+>/g, '')));
  html = html.replace(/<a href="https:\/\/conf\.local\/g\/([A-Za-z0-9_-]+)"[^>]*>([\s\S]*?)<\/a>/g,
    (_, enc, text) => resolver.acLinkAnchor(unb64url(enc), text.replace(/<[^>]+>/g, '')));

  return html;
}

module.exports = { toStorage, makeResolver };
