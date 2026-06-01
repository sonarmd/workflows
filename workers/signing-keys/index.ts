/**
 * smd-signing-keys - CI artifact signing key trust store
 *
 * KV layout (namespace: SIGNING_KEYS):
 *   chain:head              -> fingerprint of the most recently added key
 *   key:{fingerprint}       -> JSON KeyRecord (see below)
 *   config:verify_enabled   -> "true" | "false"  (default: true if absent)
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
 *   GET /keys              - all public keys concatenated (for GPG import)
 *   GET /keys/{fp}         - single public key by fingerprint
 *   GET /chain             - full chain JSON (newest -> genesis)
 *   GET /head              - current head fingerprint
 *   GET /verify-enabled    - "true" or "false" - kill switch for artifact-verify
 *   GET /healthz           - liveness + verify_enabled status
 *
 * -- Kill switch (flip remotely, zero deploy) ------------------------------
 *
 * Disable verification across all deploys immediately:
 *   curl -sf -X PUT \
 *     -H "Authorization: Bearer $CF_API_TOKEN" \
 *     "https://api.cloudflare.com/client/v4/accounts/0c4f6179a73079dd4847a690bffed296/storage/kv/namespaces/$KV_NS/values/config%3Averify_enabled" \
 *     --data "false"
 *
 * Re-enable:
 *   (same command, --data "true")
 *
 * Or use the toggle-artifact-verify GitHub Actions workflow (workflow_dispatch,
 * dropdown: enabled / disabled). No deploy, no SSH, works from a phone.
 */

export interface Env {
  SIGNING_KEYS: KVNamespace;
}

interface KeyRecord {
  fingerprint: string;
  timestamp: string;
  created_at: string;
  prev: string | null;
  public_key: string;
  reason: string;
}

interface ChainEntry {
  fingerprint: string;
  timestamp: string;
  prev: string | null;
  reason: string;
  created_at: string;
}

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Content-Type': 'text/plain; charset=utf-8',
};

const JSON_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Content-Type': 'application/json; charset=utf-8',
};

function text(body: string, extra: Record<string, string> = {}): Response {
  return new Response(body, { headers: { ...CORS_HEADERS, ...extra } });
}

function json(body: unknown): Response {
  return new Response(JSON.stringify(body, null, 2) + '\n', { headers: JSON_HEADERS });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/$/, '') || '/';

    // -- GET /healthz -----------------------------------------------------
    if (path === '/healthz') {
      const head = await env.SIGNING_KEYS.get('chain:head');
      const verifyRaw = await env.SIGNING_KEYS.get('config:verify_enabled');
      return json({ ok: true, head: head ?? null, verify_enabled: verifyRaw !== 'false' });
    }

    // -- GET /verify-enabled -----------------------------------------------
    // Kill switch consumed by the artifact-verify Ansible role.
    // Returns "true" (default when key absent) or "false" (bypass active).
    // Never cached - every Ansible run sees the live value.
    if (path === '/verify-enabled') {
      const val = await env.SIGNING_KEYS.get('config:verify_enabled');
      const enabled = val !== 'false';
      return text(enabled ? 'true' : 'false', { 'Cache-Control': 'no-store' });
    }

    // -- GET /head ---------------------------------------------------------
    if (path === '/head') {
      const head = await env.SIGNING_KEYS.get('chain:head');
      if (!head) return new Response('no keys registered\n', { status: 404, headers: CORS_HEADERS });
      return text(head + '\n');
    }

    // -- GET /keys/{fingerprint} -------------------------------------------
    const singleKeyMatch = path.match(/^\/keys\/([0-9A-Fa-f]{8,40})$/);
    if (singleKeyMatch) {
      const fp = singleKeyMatch[1].toUpperCase();
      const raw = await env.SIGNING_KEYS.get(`key:${fp}`);
      if (!raw) return new Response(`key ${fp} not found\n`, { status: 404, headers: CORS_HEADERS });
      const record = JSON.parse(raw) as KeyRecord;
      return text(record.public_key + '\n');
    }

    // -- GET /keys ---------------------------------------------------------
    // Walk chain head -> genesis, return all public keys concatenated.
    // GPG imports a multi-key armored block in one shot.
    if (path === '/keys') {
      const head = await env.SIGNING_KEYS.get('chain:head');
      if (!head) return new Response('', { status: 204, headers: CORS_HEADERS });

      const keys: string[] = [];
      let cursor: string | null = head;
      const seen = new Set<string>();

      while (cursor && !seen.has(cursor)) {
        seen.add(cursor);
        const raw = await env.SIGNING_KEYS.get(`key:${cursor}`);
        if (!raw) break;
        const record = JSON.parse(raw) as KeyRecord;
        keys.push(record.public_key.trim());
        cursor = record.prev;
      }

      return text(keys.join('\n') + '\n');
    }

    // -- GET /chain --------------------------------------------------------
    // Full chain as JSON (newest -> genesis). public_key omitted for brevity.
    if (path === '/chain') {
      const head = await env.SIGNING_KEYS.get('chain:head');
      if (!head) return json([]);

      const chain: ChainEntry[] = [];
      let cursor: string | null = head;
      const seen = new Set<string>();

      while (cursor && !seen.has(cursor)) {
        seen.add(cursor);
        const raw = await env.SIGNING_KEYS.get(`key:${cursor}`);
        if (!raw) break;
        const record = JSON.parse(raw) as KeyRecord;
        chain.push({
          fingerprint: record.fingerprint,
          timestamp:   record.timestamp,
          prev:        record.prev,
          reason:      record.reason,
          created_at:  record.created_at,
        });
        cursor = record.prev;
      }

      return json(chain);
    }

    return new Response('not found\n', { status: 404, headers: CORS_HEADERS });
  },
};
