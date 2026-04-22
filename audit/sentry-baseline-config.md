# Sentry Baseline Configuration — sonarmd

> **Purpose**: Drift detection. Every setting in the Sentry org is documented here with its expected value and reasoning. Run the audit script at the bottom to detect drift from this baseline.
>
> **Last audited**: 2026-03-15 | **Auditor**: avespoli via Claude Code
>
> **Org**: `sonarmd` | **URL**: `https://sonarmd.sentry.io`

---

## Org-Level Settings

### Security & Privacy

| Setting | Expected | Reasoning |
|---------|----------|-----------|
| `require2FA` | `true` | HIPAA requires strong authentication. All members must have 2FA enabled. |
| `enhancedPrivacy` | `true` | Hides PII in the Sentry UI (stack traces, breadcrumbs). Defense-in-depth for PHI. |
| `dataScrubber` | `true` | Strips sensitive values from event payloads before storage. |
| `dataScrubberDefaults` | `true` | Applies Sentry's built-in scrubbing rules (passwords, credit cards, SSNs, etc.). |
| `scrubIPAddresses` | `true` | HIPAA Safe Harbor lists IP addresses as one of 18 identifiers. Combined with health data = PHI. |
| `allowSuperuserAccess` | `false` | Blocks Sentry staff from accessing org data. They're not under our BAA. Re-enable temporarily if support is needed. |
| `allowSharedIssues` | `false` | Prevents creating public shareable links to error events. Error payloads could contain PHI. |
| `storeCrashReports` | `0` (disabled) | Crash report attachments (minidumps, etc.) could contain PHI in memory snapshots. |
| `genAIConsent` | `false` | No event data sent to Sentry AI features. PHI must not leave controlled environments. |
| `aggregatedDataConsent` | `false` | No aggregated data shared with Sentry for product improvement. |

### Sensitive Fields (org-level, 40 fields)

| Setting | Expected | Reasoning |
|---------|----------|-----------|
| `sensitiveFields` | `icdCode, icdGroup, diagnosis, phq2, sonar, sonarSlope, scores, prompt, supportingCopy, response, metric, data, raw, value, startDate, endDate, dateSubmitted, message, questions, notes, reason, notificationText, notificationExtras, subject, feedback, cravingManagement, triggerCode, triggerCodeInfo, smsIntroText, smsCompletionText, emailTemplate, documentUrl, notification, alert, password, salt, firebaseInstanceIdToken, originatingTwilioSmsSid, prrId, refreshToken` | Derived from crawling 95+ Mongoose schemas in triggr_api. Covers PHI (ICD codes, depression scores, health metrics, clinical notes) and AUTH (passwords, tokens, salts). SPI (name, email, phone) intentionally excluded — needed for debugging. |
| `safeFields` | `[]` (empty) | No fields explicitly excluded from scrubbing. |

### Access Control

| Setting | Expected | Reasoning |
|---------|----------|-----------|
| `hasAuthProvider` | `false` | No SSO/SAML configured. Known gap — SSO would provide single revocation point. Evaluate when budget allows. |
| `requiresSso` | `false` | Can't require SSO without a provider configured. |
| `openMembership` | `false` | Members can't self-join the org. Invitation only. |
| `allowJoinRequests` | `false` | External users can't request to join. |
| `allowMemberInvite` | `false` | Only admins/owners can send invitations. Prevents unauthorized access grants. |
| `allowMemberProjectCreation` | `false` | Members can't create new projects. Prevents unmonitored/unconfigured projects. |
| `defaultRole` | `member` | New members get least-privilege role. |

### Permissions

| Setting | Expected | Reasoning |
|---------|----------|-----------|
| `attachmentsRole` | `member` | Members can view attachments. Acceptable — attachments are scrubbed by dataScrubber. |
| `debugFilesRole` | `admin` | Only admins can access debug files (source maps, dSYMs). Contains source code. |
| `eventsMemberAdmin` | `false` | Members can't delete events. Prevents evidence tampering. |
| `alertsMemberWrite` | `true` | Members can create/edit alert rules. Acceptable — allows devs to manage their own alerts. |

### AI / Automation Features

| Setting | Expected | Reasoning |
|---------|----------|-----------|
| `hideAiFeatures` | `false` | AI features are visible in UI but `genAIConsent: false` prevents data sharing. |
| `enableSeerCoding` | `true` | Seer AI coding suggestions — operates on stack traces (already scrubbed). |
| `enableSeerEnhancedAlerts` | `true` | AI-enhanced alert grouping. Operates on scrubbed data. |
| `enablePrReviewTestGeneration` | `true` | AI test generation from error patterns. |
| `defaultAutofixAutomationTuning` | `off` | Autofix not auto-running. Manual trigger only. |
| `defaultSeerScannerAutomation` | `true` | Seer scans issues automatically for root cause. |
| `autoEnableCodeReview` | `false` | Code review not auto-enabled on new repos. |
| `autoOpenPrs` | `false` | Sentry won't auto-open PRs. |
| `defaultCodeReviewTriggers` | `["on_ready_for_review", "on_new_commit"]` | When code review IS enabled, triggers on these events. |
| `rollbackEnabled` | `true` | Allows deployment rollback suggestions. |

### Notification Settings

| Setting | Expected | Reasoning |
|---------|----------|-----------|
| `issueAlertsThreadFlag` | `true` | Issue alerts use Slack threads. Reduces channel noise. |
| `metricAlertsThreadFlag` | `true` | Metric alerts use Slack threads. |
| `githubPRBot` | `false` | No automatic PR comments from Sentry. |
| `gitlabPRBot` | `false` | No GitLab integration. |

### Sampling & Relay

| Setting | Expected | Reasoning |
|---------|----------|-----------|
| `isDynamicallySampled` | `false` | No dynamic sampling — all events captured. |
| `isEarlyAdopter` | `false` | Not on early adopter program. Stability over features. |
| `scrapeJavaScript` | `true` | Org-level JS scraping enabled. Per-project overrides below. |
| `trustedRelays` | `[]` (empty) | No Relay instances deployed. Direct SDK → Sentry. |
| `relayPiiConfig` | `null` | No custom Relay PII config (using org-level sensitiveFields instead). |

---

## Members

| Email | Role | Status | 2FA | Reasoning |
|-------|------|--------|-----|-----------|
| `avespoli@sonarmd.com` | `owner` | active | required by org | Primary owner. Full access. |
| `devadmin@sonarmd.com` | `owner` | active | required by org | Service/admin account. Second owner for bus-factor coverage. |
| `tnguyen@sonarmd.com` | `manager` | active | required by org | Team manager. Can manage projects and members. |
| `ehelena@sonarmd.com` | `member` | active | required by org | Developer. Least-privilege access. |

**Note**: `has2fa` returns `null` from API when `require2FA` is org-enforced (members can't exist without it).

---

## Teams

| Team | Members | Projects | Reasoning |
|------|---------|----------|-----------|
| `sonarmd` | 4 (avespoli, devadmin, tnguyen, ehelena) | All 8 projects | Primary and only team. `engineering` (1 member) was deleted and consolidated here. |

---

## Integrations

| Integration | Provider | ID | Status | Scopes | Findings |
|-------------|----------|----|--------|--------|----------|
| JIRA | `jira` | 295286 | active | n/a | Connected to `sonarmd.atlassian.net`. Only provides manual "Create Jira Issue" button — no auto-creation. |
| GitHub | `github` | 34722 | active | n/a (GitHub App) | Connected to `github.com/sonarmd`. **Finding**: Has `administration` permission on GitHub — unusual for error tracking. Scope down from GitHub org settings. |
| Slack | `slack` | 57626 | active | `channels:read, chat:write, chat:write.customize, chat:write.public, commands, groups:read, im:history, im:read, links:read, links:write, team:read, users:read` | **Finding**: `im:history` and `im:read` allow reading DMs where bot is a member. Sentry bundles these in their OAuth app — can't be removed without reinstalling (and reinstall would re-request them). **Mitigation**: Never add Sentry bot to DM channels. |

---

## Per-Project Settings

### Consistent Across All 8 Projects

| Setting | Expected | Reasoning |
|---------|----------|-----------|
| `resolveAge` | `720` (30 days) | Issues auto-resolve after 30 days without recurrence. Prevents stale issue pile-up. Reopen automatically if issue recurs. |
| `dataScrubber` | `true` | Inherits org-level. |
| `dataScrubberDefaults` | `true` | Inherits org-level. |
| `scrubIPAddresses` | `true` | HIPAA Safe Harbor — IP + health data = PHI. |
| `sensitiveFields` | `[]` (empty) | Inherits org-level 40 fields. No project-specific additions needed. |
| `safeFields` | `[]` (empty) | No fields excluded from scrubbing. |
| `storeCrashReports` | `null` (disabled) | Inherits org-level. |
| `groupingEnhancements` | `""` (empty) | No custom grouping rules. |
| `fingerprintingRules` | `""` (empty) | No custom fingerprinting. |
| `subjectTemplate` | `$shortID - $title` | Default template. |
| `digestsMinDelay` | `300` (5 min) | Default notification batching. |
| `digestsMaxDelay` | `1800` (30 min) | Default notification batching. |
| `team` | `sonarmd` | All projects under single team. |

### Per-Project Differences

| Project | Platform | `allowedDomains` | `verifySSL` | `scrapeJavaScript` | `groupingConfig` | `secondaryGroupingConfig` |
|---------|----------|-----------------|-------------|--------------------|-----------------|--------------------------|
| `api` | `node-express` | `api.sonarmd.com` variants (4 domains) | `true` | `false` | `newstyle:2026-01-20` | `newstyle:2023-01-11` |
| `admin` | `javascript-react` | `admin.sonarmd.com` variants (5 domains) | `true` | `false` | `newstyle:2026-01-20` | `newstyle:2023-01-11` |
| `patient` | `javascript-react` | `my.sonarmd.com` variants (5 domains) | `true` | `false` | `newstyle:2026-01-20` | `newstyle:2023-01-11` |
| `provider` | `javascript-react` | `care.sonarmd.com` variants (5 domains) | `true` | `false` | `newstyle:2026-01-20` | `null` |
| `seat` | `javascript-react` | `seat.sonarmd.com` variants (5 domains) | `true` | `false` | `newstyle:2026-01-20` | `newstyle:2023-01-11` |
| `fe-patient-app` | `react-native` | `["*"]` (intentional) | `true` | `false` | `newstyle:2023-01-11` | `null` |
| `agora` | `node-express` | `["*"]` (intentional) | `false` (blocked by private CA) | `true` | `newstyle:2026-01-20` | `null` |
| `on-machine-events` | `apple-macos` | `["*"]` (intentional) | `true` | `true` | `newstyle:2026-01-20` | `null` |

**Notes on intentional exceptions:**
- `fe-patient-app` / `agora` / `on-machine-events` `allowedDomains: ["*"]` — Not browser-based or no fixed domain. Domain restriction doesn't apply.
- `agora` `verifySSL: false` — No SSL cert on local dev machine. Will be fixed when private CA is set up.
- `agora` / `on-machine-events` `scrapeJavaScript: true` — Node/macOS projects, not browser JS. Scraping doesn't apply meaningfully.
- `fe-patient-app` `groupingConfig: newstyle:2023-01-11` — Older grouping config. Not security-relevant but should be updated to `2026-01-20` for consistency.

### DSN Key Rate Limits

| Project | Key Name | Rate Limit | Reasoning |
|---------|----------|-----------|-----------|
| `api` | Default | 500/min | Backend — highest legitimate volume during incidents. |
| `patient` | Default | 100/min | Frontend — moderate user base. |
| `provider` | Default | 100/min | Frontend — moderate user base. |
| `admin` | Default | 100/min | Internal admin panel. |
| `seat` | Default | 100/min | Internal tool. |
| `fe-patient-app` | Default | 100/min | Mobile app error volume. |
| `agora` | Default | 50/min | Internal tool — low volume by design. |
| `on-machine-events` | Default | 50/min | Machine-level events — low volume by design. |

---

## Alert Rules

| Project | Rule Name | Trigger | Action | Frequency | Notes |
|---------|-----------|---------|--------|-----------|-------|
| `agora` | agora | Every event matching frequency condition | Slack | 5 min | Custom frequency-based rule. |
| `agora` | High priority issues | New/existing high priority | Email | 30 min | Default high-priority rule. |
| `on-machine-events` | High priority issues | New/existing high priority | Email | 30 min | Default high-priority rule. |
| `admin` | New issues | First seen event | Email | 30 min | Alerts on every new issue type. |
| `api` | Basic | **Every event** | Slack | 60 min | Changed from 10 min. Still fires on every event but with 1-hour cooldown. |
| `fe-patient-app` | High priority issues | New/existing high priority | Email + Slack | 30 min | Good — targeted at high priority only. |
| `patient` | New issues | First seen event | Notify + Email + Slack | 30 min | Alerts on every new issue type. 3 notification channels. |
| `provider` | Basic | **Every event** | Slack | 60 min | Changed from 5 min. Still fires on every event but with 1-hour cooldown. |
| `seat` | Basic | **Every event** | Slack | 60 min | Changed from 5 min. Still fires on every event but with 1-hour cooldown. |

**Operational note**: `api`, `provider`, and `seat` use `EveryEventCondition` — they alert on literally every error event. This can flood Slack during incidents. Consider switching to `FirstSeenEventCondition` (new issues only) or `EventFrequencyCondition` (spike detection).

---

## Inbound Data Filters

| Project | `browser-extensions` | `filtered-transaction` | `legacy-browsers` | `localhost` | `web-crawlers` |
|---------|---------------------|----------------------|-------------------|-------------|---------------|
| `api` | on | on | off | **on** | on |
| `admin` | on | on | on (all browsers) | off | on |
| `patient` | on | on | on (all browsers) | off | on |
| `provider` | on | on | on (all browsers) | off | on |
| `seat` | on | on | on (all browsers) | off | on |
| `fe-patient-app` | off | on | off | off | off |
| `agora` | off | on | off | off | off |
| `on-machine-events` | off | on | off | off | off |

**Notes:**
- Non-browser projects (fe-patient-app, agora, on-machine-events) have browser-specific filters off — correct, they don't apply.
- `api` has `localhost: on` — filters errors from localhost. Intentional to reduce dev noise.
- Frontend apps filter legacy browser versions for all major browsers.
- No data forwarding plugins enabled (only UI tag extractors: browsers, device, os, urls).
- No service hooks configured on any project.

---

## Drift Detection Script

Run this to verify all settings match this baseline:

```bash
SENTRY_TOKEN="op://Lowkey-admin-cli/sentry-admin-token/credential" op run --no-masking -- bash -c '
ORG="sonarmd"
PASS=true
fail() { echo "DRIFT: $1 (expected: $2, got: $3)"; PASS=false; }

# Org-level
ORG_DATA=$(curl -q -s -H "Authorization: Bearer $SENTRY_TOKEN" "https://sentry.io/api/0/organizations/$ORG/")
check_org() {
  local key=$1 expected=$2
  actual=$(echo "$ORG_DATA" | jq -r ".$key")
  [ "$actual" = "$expected" ] || fail "org.$key" "$expected" "$actual"
}

check_org require2FA true
check_org enhancedPrivacy true
check_org dataScrubber true
check_org dataScrubberDefaults true
check_org scrubIPAddresses true
check_org allowSuperuserAccess false
check_org allowSharedIssues false
check_org genAIConsent false
check_org aggregatedDataConsent false
check_org openMembership false
check_org allowJoinRequests false
check_org allowMemberInvite false
check_org allowMemberProjectCreation false
check_org defaultRole member
check_org debugFilesRole admin
check_org eventsMemberAdmin false

# Sensitive fields count
SF_COUNT=$(echo "$ORG_DATA" | jq ".sensitiveFields | length")
[ "$SF_COUNT" -eq 40 ] || fail "org.sensitiveFields count" "40" "$SF_COUNT"

# Per-project
for slug in agora on-machine-events admin api fe-patient-app patient provider seat; do
  P=$(curl -q -s -H "Authorization: Bearer $SENTRY_TOKEN" "https://sentry.io/api/0/projects/$ORG/$slug/")
  check_proj() {
    local key=$1 expected=$2
    actual=$(echo "$P" | jq -r ".$key")
    [ "$actual" = "$expected" ] || fail "$slug.$key" "$expected" "$actual"
  }
  check_proj resolveAge 720
  check_proj scrubIPAddresses true
  check_proj dataScrubber true
  check_proj dataScrubberDefaults true

  # Rate limit check
  K=$(curl -q -s -H "Authorization: Bearer $SENTRY_TOKEN" "https://sentry.io/api/0/projects/$ORG/$slug/keys/")
  rl=$(echo "$K" | jq ".[0].rateLimit.count")
  [ "$rl" != "null" ] || fail "$slug.rateLimit" "set" "null"
done

# Team count
TEAMS=$(curl -q -s -H "Authorization: Bearer $SENTRY_TOKEN" "https://sentry.io/api/0/organizations/$ORG/teams/" | jq "length")
[ "$TEAMS" -eq 1 ] || fail "team count" "1" "$TEAMS"

# Member count
MEMBERS=$(curl -q -s -H "Authorization: Bearer $SENTRY_TOKEN" "https://sentry.io/api/0/organizations/$ORG/members/" | jq "length")
[ "$MEMBERS" -le 5 ] || fail "member count <= 5" "<=5" "$MEMBERS"

if [ "$PASS" = true ]; then
  echo "ALL CHECKS PASSED — no drift detected"
else
  echo "DRIFT DETECTED — review findings above"
  exit 1
fi
'
```

---

## UI-Only Settings (not auditable via API)

These settings must be verified manually in the Sentry UI:

| Setting | Location | Expected | Reasoning |
|---------|----------|----------|-----------|
| Spike Protection | Settings → Subscription → Spike Protection | Enabled (default thresholds) | Prevents quota exhaustion from error spikes. Was auto-activated/deactivated on 2026-03-13 — verify thresholds are appropriate. |
| GitHub App Permissions | GitHub → Org Settings → Installed Apps → Sentry | Remove `administration` | Error tracking tool doesn't need admin access to GitHub repos. |
| SSO/SAML | Settings → Auth | Not configured | Known gap. SSO provides single revocation point. Evaluate when budget allows. |
| Data Export | Settings → Legal & Compliance | Verify disabled | Bulk data export could exfiltrate PHI. |

---

## Change Log

| Date | Setting | Before | After | Actor | Reasoning |
|------|---------|--------|-------|-------|-----------|
| 2026-03-15 | `org.sensitiveFields` | 20 fields | 40 fields (PHI + AUTH) | avespoli | Crawled 95+ Mongoose schemas. Previous list missed ICD codes, PHQ-2 scores, health metrics, clinical notes. |
| 2026-03-15 | `org.allowSuperuserAccess` | `true` | `false` | avespoli | Sentry staff not under BAA. |
| 2026-03-15 | `api.allowedDomains` | `["*"]` | sonarmd.com variants | avespoli | Prevent DSN abuse from unauthorized domains. |
| 2026-03-15 | `on-machine-events.verifySSL` | `false` | `true` | avespoli | MITM risk on webhooks. |
| 2026-03-15 | All projects `.resolveAge` | `0` | `720` | avespoli | Stale issues never auto-resolved. |
| 2026-03-15 | 7 projects `.scrubIPAddresses` | `false` | `true` | avespoli | HIPAA Safe Harbor — IP + health data = PHI. |
| 2026-03-15 | All projects DSN `rateLimit` | `null` | 50-500/min | avespoli | Leaked DSN could exhaust quota. |
| 2026-03-15 | `engineering` team | existed (1 member) | deleted | avespoli | Consolidated into `sonarmd` team. |
| 2026-03-15 | `devadmin@sonarmd.com` invite | expired | resent + regenerated | avespoli | Org needs second owner for bus-factor. |
| 2026-03-15 | `api` alert frequency | `10` min | `60` min | avespoli | EveryEvent + 10 min cooldown was spamming Slack. |
| 2026-03-15 | `provider` alert frequency | `5` min | `60` min | avespoli | EveryEvent + 5 min cooldown was spamming Slack. |
| 2026-03-15 | `seat` alert frequency | `5` min | `60` min | avespoli | EveryEvent + 5 min cooldown was spamming Slack. |
