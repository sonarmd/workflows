// Safety gate. Runs on every authored page BEFORE it can be uploaded. A page that fails
// any check is SKIPPED (not uploaded) and the reason logged; the gate never throws, so a
// bad page can never fail a deploy. Returns { ok, violations[] }.
//
// Checks:
//   - ASCII only (the global ASCII law; tab/LF/CR + 0x20-0x7E)
//   - no obvious secrets (high-signal patterns only, to avoid false positives)
//   - no PHI markers (the canon must be PHI-free; team-role names only)

const NON_ASCII = /[^\x09\x0A\x0D\x20-\x7E]/;

// High-signal secret patterns. Deliberately narrow: catch real credentials, not prose.
const SECRET_PATTERNS = [
  { name: 'aws-access-key-id', re: /\bAKIA[0-9A-Z]{16}\b/ },
  { name: 'private-key-block', re: /-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----/ },
  { name: 'github-token', re: /\bgh[pousr]_[A-Za-z0-9]{36,}\b/ },
  { name: 'slack-token', re: /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/ },
  { name: 'bearer-jwt', re: /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/ },
  { name: 'generic-secret-assign', re: /\b(?:api[_-]?key|secret|password|passwd|token)\s*[:=]\s*['"][^'"\s]{12,}['"]/i },
];

// PHI markers. Heuristic; the canon is generated from architecture, not patient data, so a
// hit almost always means the author pulled in something it should not have.
const PHI_PATTERNS = [
  { name: 'ssn', re: /\b\d{3}-\d{2}-\d{4}\b/ },
  { name: 'mrn-label', re: /\b(?:MRN|medical record number)\s*[:#]?\s*\d{4,}\b/i },
  { name: 'dob-label', re: /\b(?:DOB|date of birth)\s*[:#]?\s*\d/i },
];

function scan(text) {
  const violations = [];
  if (NON_ASCII.test(text)) {
    const ch = text.match(NON_ASCII)[0];
    violations.push({ kind: 'non-ascii', detail: `0x${ch.codePointAt(0).toString(16)}` });
  }
  for (const p of SECRET_PATTERNS) if (p.re.test(text)) violations.push({ kind: 'secret', detail: p.name });
  for (const p of PHI_PATTERNS) if (p.re.test(text)) violations.push({ kind: 'phi', detail: p.name });
  return { ok: violations.length === 0, violations };
}

module.exports = { scan };
