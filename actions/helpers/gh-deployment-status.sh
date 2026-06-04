#!/usr/bin/env bash
# gh-deployment-status.sh
#
# Post a deployment status to the GitHub Deployments API. Called by the Ansible
# runner at deploy completion to flip the GitHub Environments icon and trigger
# the Atlassian for GitHub app's Jira deploy panel update.
#
# Required env: GH_TOKEN (PAT or App token with deployments: write on the repo).
#
# Usage:
#   gh-deployment-status.sh \
#     --repo <owner/name> --deployment-id <id> --state <state> \
#     [--log-url <url>] [--environment-url <url>] [--description <text>]
#
# State map (GitHub-side icon):
#   queued       grey
#   in_progress  spinner / white
#   success      green
#   failure      red
#   error        red (treat as failure)
#   inactive     grey (used to mark prior deployments stale)
#
# Exit codes:
#   0  - status posted
#   1  - missing required arg or token
#   2  - GitHub API rejected the call
set -euo pipefail

die() { echo "gh-deployment-status: $*" >&2; exit 1; }

REPO="" DEPLOYMENT_ID="" STATE=""
LOG_URL="" ENVIRONMENT_URL="" DESCRIPTION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)            REPO="$2"; shift 2 ;;
    --deployment-id)   DEPLOYMENT_ID="$2"; shift 2 ;;
    --state)           STATE="$2"; shift 2 ;;
    --log-url)         LOG_URL="$2"; shift 2 ;;
    --environment-url) ENVIRONMENT_URL="$2"; shift 2 ;;
    --description)     DESCRIPTION="$2"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN env is required"
[ -n "$REPO" ]          || die "missing --repo"
[ -n "$DEPLOYMENT_ID" ] || die "missing --deployment-id"
[ -n "$STATE" ]         || die "missing --state"

case "$STATE" in
  queued|in_progress|success|failure|error|inactive) : ;;
  *) die "invalid state: $STATE (queued|in_progress|success|failure|error|inactive)" ;;
esac

PAYLOAD=$(jq -n \
  --arg state "$STATE" \
  --arg log_url "$LOG_URL" \
  --arg env_url "$ENVIRONMENT_URL" \
  --arg desc "$DESCRIPTION" \
  '{
    state: $state,
    log_url: (if $log_url == "" then null else $log_url end),
    environment_url: (if $env_url == "" then null else $env_url end),
    description: (if $desc == "" then null else $desc end)
  } | with_entries(select(.value != null))')

RESP=$(curl -sS -X POST \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  --data "$PAYLOAD" \
  "https://api.github.com/repos/$REPO/deployments/$DEPLOYMENT_ID/statuses")

ID=$(jq -r '.id // empty' <<< "$RESP")
if [ -z "$ID" ]; then
  echo "gh-deployment-status: API rejected payload" >&2
  echo "$RESP" >&2
  exit 2
fi

echo "gh-deployment-status: posted state=$STATE deployment_id=$DEPLOYMENT_ID status_id=$ID"
