# Secrets Inventory — triggr_api

All secrets below are currently in Ansible Vault (`triggr_misc/Ansible/group_vars/*/secrets.yml`).
Migrate each to a per-environment 1Password vault before ECS cutover.

## Vault Structure

| Vault | Purpose | Service Account Access |
|-------|---------|----------------------|
| `smd_cicd_dev` | Dev secrets | Dev deploy pipeline only |
| `smd_cicd_stg` | Staging secrets | Stg deploy pipeline only |
| `smd_cicd_prd` | Production secrets | Prd deploy pipeline only (restricted) |

Each vault gets its own 1Password Service Account. The GitHub org secret
`OP_SERVICE_ACCOUNT_TOKEN` is set per GitHub Environment (dev, stg, prd)
so each pipeline only has access to its own vault.

## Per-Environment Secrets (29 per vault)

| Env Var | Ansible Variable | 1Password Item |
|---------|-----------------|----------------|
| `MONGO_PASSWORD` | `mongo_password` | `mongo-password` |
| `MONGO_READ_ONLY_PASSWORD` | `mongo_read_only_password` | `mongo-read-only-password` |
| `SESSION_SECRET` | `session_secret` | `session-secret` |
| `JWT_SECRET` | `jwt_secret` | `jwt-secret` |
| `FIREBASE_SERVER_KEY` | `firebase_server_key` | `firebase-server-key` |
| `GITHUB_OAUTH_SECRET` | `github_secret` | `github-oauth-secret` |
| `GCAL_CLIENT_SECRET` | `gcal_client_secret` | `gcal-client-secret` |
| `GCAL_REFRESH_TOKEN` | `gcal_refresh_token` | `gcal-refresh-token` |
| `BRITEVERIFY_API_KEY` | `briteverify_api_key` | `briteverify-api-key` |
| `CHANGE_HEALTHCARE_CLIENT_ID` | `change_healthcare_client_id` | `change-healthcare-client-id` |
| `CHANGE_HEALTHCARE_CLIENT_SECRET` | `change_healthcare_client_secret` | `change-healthcare-client-secret` |
| `ITERABLE_API_KEY` | `iterable_api_key` | `iterable-api-key` |
| `ITERABLE_WEBHOOK_PASSWORD` | `webhookPassword` | `iterable-webhook-password` |
| `MIXPANEL_MOBILE_API_SECRET` | `mixpanel_mobile_api_secret` | `mixpanel-mobile-api-secret` |
| `MIXPANEL_MOBILE_TOKEN` | `mixpanel_mobile_token` | `mixpanel-mobile-token` |
| `PAGERDUTY_KEY_LOW_PRIORITY` | `eng_pager_duty_key_low_priority` | `pagerduty-key-low` |
| `PAGERDUTY_KEY_HIGH_PRIORITY` | `eng_pager_duty_key_high_priority` | `pagerduty-key-high` |
| `REDIS_AUTH_TOKEN` | `redis_auth_token` | `redis-auth-token` |
| `SENDGRID_API_KEY` | `sendgrid_api_key` | `sendgrid-api-key` |
| `SLACK_BOT_TOKEN` | `slack_bot_token` | `slack-bot-token` |
| `SLACK_COMMUNITY_WEBHOOK_VERIFICATION_TOKEN` | `slack_community_webhook_verification_token` | `slack-verification-token` |
| `TWILIO_AUTH_TOKEN` | `twilio_auth_token` | `twilio-auth-token` |
| `TWILIO_API_KEY` | `twilio_api_key` | `twilio-api-key` |
| `TWILIO_API_SECRET` | `twilio_api_secret` | `twilio-api-secret` |
| `TWILIO_OUTGOING_PHONE_NUMBER` | `twilio_outgoing_phone_number` | `twilio-outgoing-phone` |
| `TWILIO_DEFAULT_SMS_PHONE_NUMBER` | `twilio_default_sms_phone_number` | `twilio-default-sms-phone` |
| `TWILIO_OUTBOUND_PHONE_NUMBERS` | `twilio_outbound_phone_numbers` | `twilio-outbound-phones` |
| `TWILIO_IVR_FLOW_SID` | `twilio_ivr_flow_sid` | `twilio-ivr-flow-sid` |
| `TWILIO_VOICE_APP_SID` | `twilio_voice_app_sid` | `twilio-voice-app-sid` |

**Total: 29 secrets x 3 vaults = 87 items**

## Webhook URLs (currently cleartext in group_vars but contain tokens)

These Slack webhook URLs are currently stored as cleartext in Ansible group_vars.
They contain embedded tokens and should be treated as secrets.

| Env Var | Source | Environments |
|---------|--------|-------------|
| `SLACK_CLAIMS_WEBHOOK` | `claims_webhook` | Same across all envs |
| `SLACK_UNDELIVERABLE_EMAIL_ALERTS_WEBHOOK` | `undeliverable_email_alerts_webhook` | dev/stg share, prd different |
| `SLACK_UNDELIVERABLE_MESSAGE_ALERTS_WEBHOOK_URL` | `undeliverable_message_alerts_webhook_url` | dev/stg share, prd different |

**Total: 3 additional secrets to migrate**

## Migration Steps

1. Create three vaults in 1Password: `smd_cicd_dev`, `smd_cicd_stg`, `smd_cicd_prd`
2. Create a Service Account per vault (or one with access to all three if preferred)
3. Decrypt Ansible Vault: `cd triggr_misc/Ansible && ansible-vault decrypt group_vars/*/secrets.yml`
4. For each secret per environment, create a 1Password item:
   ```bash
   op item create --vault smd_cicd_dev --category=api-credential \
     --title="mongo-password" \
     --fields "credential={value}"
   ```
5. Re-encrypt: `ansible-vault encrypt group_vars/*/secrets.yml`
6. Set `OP_SERVICE_ACCOUNT_TOKEN` per GitHub Environment (dev, stg, prd)
7. Verify by running `generate-config.js` with `op run --env-file` and diffing against Ansible-generated config
