#!/usr/bin/env bash
# slack-status-tick.sh
#
# Update an existing Slack deploy message in place via chat.update. Refreshes
# the status emoji in the header and the Elapsed field, otherwise preserves
# the original Block Kit layout produced by the slack-deploy-message action.
#
# Designed for the Ansible runner: call once at deploy start with state=in_progress,
# repeat on a 30s tick refreshing elapsed, call once at end with state=success or
# state=failure. The message identity is the (channel, ts) pair returned by the
# original chat.postMessage.
#
# Required env: SLACK_BOT_TOKEN
#
# Usage:
#   slack-status-tick.sh \
#     --channel <C123> --ts <1234567890.0001> \
#     --app <name> --env <stg|prd> --tag <release-tag> --sha <full_sha> \
#     --artifact-url <url> --gh-run-url <url> --deployment-id <id> \
#     --started-at <iso8601> \
#     --state <queued|in_progress|success|failure> \
#     --elapsed-seconds <n>
#
# Exit codes:
#   0  - update succeeded
#   1  - missing required arg or token
#   2  - Slack API rejected the call
set -euo pipefail

require() { [ -n "${!1:-}" ] || { echo "slack-status-tick: missing $1" >&2; exit 1; }; }
die()     { echo "slack-status-tick: $*" >&2; exit 1; }

CHANNEL="" TS="" APP="" ENV_NAME="" TAG="" SHA=""
ARTIFACT_URL="" GH_RUN_URL="" DEPLOYMENT_ID=""
STARTED_AT="" STATE="" ELAPSED_SECONDS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --channel)         CHANNEL="$2"; shift 2 ;;
    --ts)              TS="$2"; shift 2 ;;
    --app)             APP="$2"; shift 2 ;;
    --env)             ENV_NAME="$2"; shift 2 ;;
    --tag)             TAG="$2"; shift 2 ;;
    --sha)             SHA="$2"; shift 2 ;;
    --artifact-url)    ARTIFACT_URL="$2"; shift 2 ;;
    --gh-run-url)      GH_RUN_URL="$2"; shift 2 ;;
    --deployment-id)   DEPLOYMENT_ID="$2"; shift 2 ;;
    --started-at)      STARTED_AT="$2"; shift 2 ;;
    --state)           STATE="$2"; shift 2 ;;
    --elapsed-seconds) ELAPSED_SECONDS="$2"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done

require SLACK_BOT_TOKEN
for v in CHANNEL TS APP ENV_NAME TAG SHA ARTIFACT_URL GH_RUN_URL DEPLOYMENT_ID STARTED_AT STATE ELAPSED_SECONDS; do
  [ -n "${!v}" ] || die "missing --$(echo "$v" | tr 'A-Z_' 'a-z-')"
done

case "$STATE" in
  queued)      EMOJI=":black_circle:";        VERB="Queued" ;;
  in_progress) EMOJI=":white_circle:";        VERB="Deploying" ;;
  success)     EMOJI=":large_green_circle:";  VERB="Deployed" ;;
  failure)     EMOJI=":red_circle:";          VERB="Failed deploy of" ;;
  *) die "unknown state: $STATE (queued|in_progress|success|failure)" ;;
esac

# Format elapsed as Hh Mm Ss / Mm Ss / Ss.
if [ "$ELAPSED_SECONDS" -ge 3600 ]; then
  ELAPSED_HUMAN=$(printf '%dh%dm%ds' $((ELAPSED_SECONDS/3600)) $(((ELAPSED_SECONDS%3600)/60)) $((ELAPSED_SECONDS%60)))
elif [ "$ELAPSED_SECONDS" -ge 60 ]; then
  ELAPSED_HUMAN=$(printf '%dm%ds' $((ELAPSED_SECONDS/60)) $((ELAPSED_SECONDS%60)))
else
  ELAPSED_HUMAN="${ELAPSED_SECONDS}s"
fi

SHORT_SHA="${SHA:0:7}"
TRIGGER_TEXT="deploy $ENV_NAME $APP $TAG $ARTIFACT_URL"

BLOCKS=$(jq -n \
  --arg emoji "$EMOJI" --arg verb "$VERB" --arg app "$APP" --arg env "$ENV_NAME" \
  --arg tag "$TAG" --arg sha "$SHORT_SHA" --arg started "$STARTED_AT" \
  --arg elapsed "$ELAPSED_HUMAN" --arg gh "$GH_RUN_URL" --arg art "$ARTIFACT_URL" \
  --arg did "$DEPLOYMENT_ID" --arg trigger "$TRIGGER_TEXT" \
  '[
    { type: "header",
      text: { type: "plain_text", text: ($emoji + " " + $verb + " " + $app + " to " + $env), emoji: true } },
    { type: "section",
      fields: [
        { type: "mrkdwn", text: ("*App*\n" + $app) },
        { type: "mrkdwn", text: ("*Env*\n" + $env) },
        { type: "mrkdwn", text: ("*Tag*\n`" + $tag + "`") },
        { type: "mrkdwn", text: ("*SHA*\n`" + $sha + "`") },
        { type: "mrkdwn", text: ("*Started*\n" + $started) },
        { type: "mrkdwn", text: ("*Elapsed*\n" + $elapsed) }
      ] },
    { type: "context",
      elements: [
        { type: "mrkdwn", text: ("<" + $gh + "|GitHub run> | <" + $art + "|Artifact> | deployment_id: " + $did) }
      ] },
    { type: "divider" },
    { type: "section",
      text: { type: "mrkdwn", text: ("`" + $trigger + "`") } }
  ]')

PAYLOAD=$(jq -n \
  --arg ch "$CHANNEL" --arg ts "$TS" --arg text "$TRIGGER_TEXT" --argjson blocks "$BLOCKS" \
  '{ channel: $ch, ts: $ts, text: $text, blocks: $blocks }')

RESP=$(curl -sS -X POST https://slack.com/api/chat.update \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data "$PAYLOAD")

OK=$(jq -r '.ok' <<< "$RESP")
if [ "$OK" != "true" ]; then
  ERR=$(jq -r '.error // "unknown"' <<< "$RESP")
  echo "slack-status-tick: chat.update failed: $ERR" >&2
  exit 2
fi

echo "slack-status-tick: state=$STATE elapsed=$ELAPSED_HUMAN ts=$TS"
