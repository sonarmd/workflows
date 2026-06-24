// Minimal Confluence REST client: find page by title, create-or-update by title, apply
// labels, and back-link an existing page to a new one. Idempotent by design. Honors a
// dry-run mode (no network): every mutating call is logged and returns a synthetic result,
// so the whole publish flow can be exercised locally without credentials.
//
// Auth + base url come from the caller (injected by 1Password/load-secrets in CI).

class Confluence {
  constructor({ baseUrl, user, token, spaceKey, dryRun }) {
    this.baseUrl = (baseUrl || '').replace(/\/$/, '');
    this.user = user;
    this.token = token;
    this.spaceKey = spaceKey;
    this.dryRun = !!dryRun;
    this._dryIds = 0;
  }

  _headers() {
    return {
      Authorization: 'Basic ' + Buffer.from(`${this.user}:${this.token}`).toString('base64'),
      'Content-Type': 'application/json',
      Accept: 'application/json',
    };
  }

  async _api(method, route, body) {
    if (this.dryRun && method !== 'GET') {
      console.log(`[dry-run] ${method} ${route}`);
      return { id: `dry-${++this._dryIds}`, _dryRun: true };
    }
    const res = await fetch(this.baseUrl + route, {
      method, headers: this._headers(), body: body ? JSON.stringify(body) : undefined,
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Confluence ${method} ${route} -> ${res.status}: ${text.slice(0, 300)}`);
    }
    return res.status === 204 ? null : res.json();
  }

  async findByTitle(title) {
    if (this.dryRun) return null; // treat everything as new in dry-run
    const q = `/rest/api/content?spaceKey=${encodeURIComponent(this.spaceKey)}` +
      `&title=${encodeURIComponent(title)}&expand=version,body.storage`;
    const data = await this._api('GET', q);
    return (data.results && data.results[0]) || null;
  }

  // Create or update a page by title. Returns { id, action }.
  async upsert({ title, storage, parentId, labels }) {
    const existing = await this.findByTitle(title);
    const doc = {
      type: 'page', title, space: { key: this.spaceKey },
      body: { storage: { value: storage, representation: 'storage' } },
    };
    if (parentId) doc.ancestors = [{ id: parentId }];

    let page, action;
    if (existing) {
      doc.version = { number: existing.version.number + 1 };
      page = await this._api('PUT', `/rest/api/content/${existing.id}`, doc);
      action = 'update';
    } else {
      page = await this._api('POST', '/rest/api/content', doc);
      action = 'create';
    }
    if (labels && labels.length) {
      await this._api('POST', `/rest/api/content/${page.id}/label`,
        labels.map((name) => ({ prefix: 'global', name })));
    }
    return { id: page.id, action };
  }

  // Append a link to newTitle at the bottom of an existing page (by title). Idempotent:
  // if a link to newTitle already exists in the body, do nothing.
  async backlink(fromTitle, newTitle) {
    if (this.dryRun) {
      console.log(`[dry-run] backlink "${fromTitle}" -> "${newTitle}"`);
      return { action: 'backlink', _dryRun: true };
    }
    const page = await this.findByTitle(fromTitle);
    if (!page) return { action: 'skip', reason: 'from-page-not-found' };
    const body = (page.body && page.body.storage && page.body.storage.value) || '';
    if (body.includes(`ri:content-title="${newTitle}"`)) return { action: 'noop' };
    const linkMacro =
      `<p><strong>Related:</strong> <ac:link><ri:page ri:content-title="${newTitle}" />` +
      `<ac:plain-text-link-body><![CDATA[${newTitle}]]></ac:plain-text-link-body></ac:link></p>`;
    const doc = {
      type: 'page', title: fromTitle, space: { key: this.spaceKey },
      version: { number: page.version.number + 1 },
      body: { storage: { value: body + linkMacro, representation: 'storage' } },
    };
    await this._api('PUT', `/rest/api/content/${page.id}`, doc);
    return { action: 'backlink' };
  }
}

module.exports = { Confluence };
