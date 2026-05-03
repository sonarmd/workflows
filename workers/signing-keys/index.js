/**
 * smd-signing-keys — CI artifact signing key trust store
 *
 * KV layout (namespace: SIGNING_KEYS):
 *   chain:head              → fingerprint of the most recently added key
 *   key:{fingerprint}       → JSON KeyRecord (see below)
 *
 * KeyRecord {
 *   fingerprint: string       GPG key fingerprint (40-char hex)
 *   timestamp:   string       ISO-8601 UTC, e.g. "2026-05-03T010203Z"
 *   prev:        string|null  fingerprint of the preceding key (null = genesis)
 *   public_key:  string       armored GPG public key block
 *   reason:      string       why this key was generated
 *   created_at:  string       ISO-8601 UTC wall clock at write time
 * }
 *
 * Endpoints:
 *   GET /keys          — all public keys concatenated (for GPG import)
 *   GET /keys/{fp}     — single public key by fingerprint
 *   GET /chain         — full chain JSON (newest → genesis)
 *   GET /head          — current head fingerprint
 *   GET /healthz       — liveness check
 */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Content-Type': 'text/plain; charset=utf-8',
};

const JSON_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Content-Type': 'application/json; charset=utf-8',
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/$/, '') || '/';

    // ── GET /healthz ───────────────────────────────────────────────────────
    if (path === '/healthz') {
      const head = await env.SIGNING_KEYS.get('chain:head');
      return new Response(
        JSON.stringify({ ok: true, head: head ?? null }),
        { headers: JSON_HEADERS }
      );
    }

    // ── GET /head ──────────────────────────────────────────────────────────
    if (path === '/head') {
      const head = await env.SIGNING_KEYS.get('chain:head');
      if (!head) {
        return new Response('no keys registered\n', { status: 404, headers: CORS });
      }
      return new Response(head + '\n', { headers: CORS });
    }

    // ── GET /keys/{fingerprint} ────────────────────────────────────────────
    const singleKeyMatch = path.match(/^\/keys\/([0-9A-Fa-f]{8,40})$/);
    if (singleKeyMatch) {
      const fp = singleKeyMatch[1].toUpperCase();
      const raw = await env.SIGNING_KEYS.get(`key:${fp}`);
      if (!raw) {
        return new Response(`key ${fp} not found\n`, { status: 404, headers: CORS });
      }
      const record = JSON.parse(raw);
      return new Response(record.public_key + '\n', { headers: CORS });
    }

    // ── GET /keys ─────────────────────────────────────────────────────────
    // Walk the chain from head → genesis and return all public keys
    // concatenated. GPG can import a multi-key armored block in one shot.
    if (path === '/keys') {
      const head = await env.SIGNING_KEYS.get('chain:head');
      if (!head) {
        return new Response('', { status: 204, headers: CORS });
      }

      const keys = [];
      let cursor = head;
      const seen = new Set();

      while (cursor && !seen.has(cursor)) {
        seen.add(cursor);
        const raw = await env.SIGNING_KEYS.get(`key:${cursor}`);
        if (!raw) break;
        const record = JSON.parse(raw);
        keys.push(record.public_key.trim());
        cursor = record.prev ?? null;
      }

      return new Response(keys.join('\n') + '\n', { headers: CORS });
    }

    // ── GET /chain ────────────────────────────────────────────────────────
    // Full chain as JSON, newest first. public_key omitted for brevity
    // (use /keys or /keys/{fp} to retrieve the actual key material).
    if (path === '/chain') {
      const head = await env.SIGNING_KEYS.get('chain:head');
      if (!head) {
        return new Response('[]', { headers: JSON_HEADERS });
      }

      const chain = [];
      let cursor = head;
      const seen = new Set();

      while (cursor && !seen.has(cursor)) {
        seen.add(cursor);
        const raw = await env.SIGNING_KEYS.get(`key:${cursor}`);
        if (!raw) break;
        const record = JSON.parse(raw);
        chain.push({
          fingerprint: record.fingerprint,
          timestamp:   record.timestamp,
          prev:        record.prev,
          reason:      record.reason,
          created_at:  record.created_at,
        });
        cursor = record.prev ?? null;
      }

      return new Response(JSON.stringify(chain, null, 2) + '\n', {
        headers: JSON_HEADERS,
      });
    }

    return new Response('not found\n', { status: 404, headers: CORS });
  },
};
