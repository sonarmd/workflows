# Secrets Inventory

## 1Password Vault: `smd_cicd`

Organization-level vault for CI/CD secrets. Accessed via Service Account token.

### GitHub Org Secret

| Secret Name | Purpose |
|------------|---------|
| `OP_SERVICE_ACCOUNT_TOKEN` | 1Password Service Account — resolves all `op://` references |

### GitHub Repository Variables (not secrets — non-sensitive)

| Variable | Repo | Purpose |
|----------|------|---------|
| `AWS_DEPLOY_ROLE_ARN` | All | IAM role ARN for OIDC |
| `CF_DIST_ADMIN_STG` | frontend | CloudFront distribution ID |
| `CF_DIST_PATIENT_STG` | frontend | CloudFront distribution ID |
| `CF_DIST_PROVIDER_STG` | frontend | CloudFront distribution ID |
| `CF_DIST_SEAT_STG` | frontend | CloudFront distribution ID |
| `CF_DIST_ADMIN_PRD` | frontend | CloudFront distribution ID |
| `CF_DIST_PATIENT_PRD` | frontend | CloudFront distribution ID |
| `CF_DIST_PROVIDER_PRD` | frontend | CloudFront distribution ID |
| `CF_DIST_SEAT_PRD` | frontend | CloudFront distribution ID |

### 1Password Items: API Config Secrets

One item per environment: `API/dev/config-secrets`, `API/stg/config-secrets`, `API/prd/config-secrets`

Each item contains these fields (migrated from Ansible Vault):

| Field | Source (Ansible) | Notes |
|-------|-----------------|-------|
| `mongo_uri` | `mongo_uri` | MongoDB connection string |
| `mongo_username` | `mongo_username` | |
| `mongo_password` | `mongo_password` | |
| `mongo_url` | `mongo_url` | |
| `mongo_prefix` | `mongo_prefix` | |
| `mongo_read_only_uri` | `mongo_read_only_uri` | |
| `mongo_read_only_username` | `mongo_read_only_username` | |
| `mongo_read_only_password` | `mongo_read_only_password` | |
| `session_secret` | `session_secret` | |
| `jwt_secret` | `jwt_secret` | |
| `twilio_auth_token` | `twilio_auth_token` | |
| `twilio_api_key` | `twilio_api_key` | |
| `twilio_api_secret` | `twilio_api_secret` | |
| `sendgrid_api_key` | `sendgrid_api_key` | |
| `slack_bot_token` | `slack_bot_token` | |
| `redis_auth_token` | `redis_auth_token` | |
| `firebase_server_key` | `firebase_server_key` | |
| `github_oauth_secret` | `github_secret` | Renamed for clarity |
| `gcal_client_secret` | `gcal_client_secret` | |
| `gcal_refresh_token` | `gcal_refresh_token` | |
| `iterable_api_key` | `iterable_api_key` | |
| `change_healthcare_client_id` | `change_healthcare_client_id` | |
| `change_healthcare_client_secret` | `change_healthcare_client_secret` | |
| `pagerduty_key_low_priority` | `eng_pager_duty_key_low_priority` | Renamed |
| `pagerduty_key_high_priority` | `eng_pager_duty_key_high_priority` | Renamed |
| `mixpanel_api_secret` | `mixpanel_mobile_api_secret` | |
| `mixpanel_token` | `mixpanel_mobile_token` | |
| `briteverify_api_key` | `briteverify_api_key` | |

### 1Password Items: Infrastructure Secrets

| Item | Fields | Purpose |
|------|--------|---------|
| `Slack/deploy-webhook` | `credential` | Webhook URL for #ops channel |
| `Slack/metrics-webhook` | `credential` | Webhook URL for #engineering-metrics |
| `Mobile/expo-token` | `credential` | EXPO_TOKEN for EAS CLI |
| `Mobile/asc-api-key` | `credential` | App Store Connect API key |
| `Mobile/play-service-account` | `credential` | Google Play service account JSON |
| `Sentry/auth-token` | `credential` | Sentry release integration token |

## Migration Procedure: Ansible Vault → 1Password

### For each environment (dev, stg, prd):

1. Decrypt the Ansible vault file:
   ```bash
   cd ~/code/all/triggr_misc/Ansible
   ansible-vault decrypt group_vars/<env>/secrets.yml --vault-password-file ~/triggr-vault-password.txt
   ```

2. Create the 1Password item:
   ```bash
   op item create --vault smd_cicd \
     --category "Secure Note" \
     --title "API/<env>/config-secrets" \
     # Add each field from the decrypted secrets.yml
   ```

3. Re-encrypt the Ansible file:
   ```bash
   ansible-vault encrypt group_vars/<env>/secrets.yml --vault-password-file ~/triggr-vault-password.txt
   ```

4. Verify by generating config and comparing:
   ```bash
   # Generate from 1Password template
   # Compare with Ansible-rendered output byte-for-byte
   diff generated.json ansible-rendered.json
   ```

### Important: Do NOT delete the Ansible Vault files until the migration is fully validated in production.
