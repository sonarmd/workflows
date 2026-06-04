#!/usr/bin/env bash
# confluence-deploy-log-finalize.sh
#
# Finalize the State and Duration cells of a previously appended row in the
# Confluence Deploy Log. Identifies the row by its row_id (returned by the
# confluence-deploy-log-append action). Never touches any other row; never
# deletes anything. Append-only semantics.
#
# Required env: CONFLUENCE_TOKEN (scoped Atlassian API token under a service
#                account; used as Authorization: Bearer)
#
# Usage:
#   confluence-deploy-log-finalize.sh \
#     --base-url <https://sonarmd.atlassian.net> \
#     --page-id <id> --row-id <id> \
#     --state <success|failure> --duration <human-readable>
#
# Exit codes:
#   0  - row updated
#   1  - missing required arg or token
#   2  - row marker not found in page
#   3  - Confluence API rejected the call
set -euo pipefail

die() { echo "confluence-deploy-log-finalize: $*" >&2; exit 1; }

BASE_URL="" PAGE_ID="" ROW_ID="" STATE="" DURATION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --page-id)  PAGE_ID="$2";  shift 2 ;;
    --row-id)   ROW_ID="$2";   shift 2 ;;
    --state)    STATE="$2";    shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[ -n "${CONFLUENCE_TOKEN:-}" ] || die "CONFLUENCE_TOKEN env required"
[ -n "$BASE_URL" ] || die "missing --base-url"
[ -n "$PAGE_ID" ]  || die "missing --page-id"
[ -n "$ROW_ID" ]   || die "missing --row-id"
[ -n "$STATE" ]    || die "missing --state"
[ -n "$DURATION" ] || die "missing --duration"

case "$STATE" in
  success|failure|error) : ;;
  *) die "invalid --state: $STATE (success|failure|error)" ;;
esac

PAGE=$(curl -sS \
  -H "Authorization: Bearer $CONFLUENCE_TOKEN" \
  -H 'Accept: application/json' \
  "$BASE_URL/wiki/api/v2/pages/$PAGE_ID?body-format=storage")

TITLE=$(jq -r '.title' <<< "$PAGE")
CURRENT_VERSION=$(jq -r '.version.number' <<< "$PAGE")
CURRENT_BODY=$(jq -r '.body.storage.value' <<< "$PAGE")

if [ "$TITLE" = "null" ] || [ -z "$TITLE" ]; then
  echo "confluence-deploy-log-finalize: failed to fetch page $PAGE_ID" >&2
  echo "$PAGE" >&2
  exit 3
fi

NEXT_VERSION=$((CURRENT_VERSION + 1))

NEW_BODY=$(ROW_ID="$ROW_ID" STATE="$STATE" DURATION="$DURATION" python3 - <<'PY'
import os, re, sys, html

body = sys.stdin.read()
row_id   = os.environ['ROW_ID']
state    = html.escape(os.environ['STATE'], quote=True)
duration = html.escape(os.environ['DURATION'], quote=True)

state_re    = re.compile(r'<span data-cell="state-'    + re.escape(row_id) + r'">[^<]*</span>')
duration_re = re.compile(r'<span data-cell="duration-' + re.escape(row_id) + r'">[^<]*</span>')

if not state_re.search(body):
    sys.stderr.write(f"row marker state-{row_id} not found\n")
    sys.exit(2)
if not duration_re.search(body):
    sys.stderr.write(f"row marker duration-{row_id} not found\n")
    sys.exit(2)

body = state_re.sub(
    f'<span data-cell="state-{row_id}">{state}</span>', body, count=1)
body = duration_re.sub(
    f'<span data-cell="duration-{row_id}">{duration}</span>', body, count=1)

sys.stdout.write(body)
PY
<<< "$CURRENT_BODY") || {
  rc=$?
  if [ "$rc" -eq 2 ]; then exit 2; fi
  exit "$rc"
}

PAYLOAD=$(jq -n \
  --arg id "$PAGE_ID" --arg title "$TITLE" --arg body "$NEW_BODY" \
  --argjson version "$NEXT_VERSION" --arg row_id "$ROW_ID" --arg state "$STATE" \
  '{
    id: $id,
    status: "current",
    title: $title,
    body: { representation: "storage", value: $body },
    version: { number: $version, message: ("deploy log finalize row " + $row_id + " state=" + $state) }
  }')

RESP=$(curl -sS \
  -X PUT \
  -H "Authorization: Bearer $CONFLUENCE_TOKEN" \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  --data "$PAYLOAD" \
  "$BASE_URL/wiki/api/v2/pages/$PAGE_ID")

NEW_VERSION=$(jq -r '.version.number // empty' <<< "$RESP")
if [ -z "$NEW_VERSION" ]; then
  echo "confluence-deploy-log-finalize: PUT failed" >&2
  echo "$RESP" >&2
  exit 3
fi

echo "confluence-deploy-log-finalize: row_id=$ROW_ID state=$STATE duration=$DURATION version=$NEW_VERSION"
