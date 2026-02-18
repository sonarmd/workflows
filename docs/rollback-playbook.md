# Rollback Playbook

## Frontend (S3 + CloudFront)

### Option 1: Re-deploy Previous Tag (~2 min)

```bash
# Find the previous working tag
git tag --list 'stg-fe-*' --sort=-v:refname | head -5

# Deploy it via break-glass
# Go to: GitHub Actions → Break-Glass Manual Deploy → Run workflow
# Environment: stg (or prd)
# Tag override: stg-fe-1.2.2-b41 (the previous working tag)
# Reason: "Rollback from stg-fe-1.2.3-b42 due to [reason]"
```

### Option 2: Instant S3 Version Restore (~30s)

For `index.html`-only issues (JS assets are content-hashed and immutable):

```bash
# List previous versions of index.html
aws s3api list-object-versions \
  --bucket admin.stg.sonarmd.com \
  --prefix index.html \
  --max-items 5

# Restore previous version
aws s3api copy-object \
  --bucket admin.stg.sonarmd.com \
  --copy-source admin.stg.sonarmd.com/index.html?versionId=PREVIOUS_VERSION_ID \
  --key index.html \
  --cache-control "max-age=300, public" \
  --content-type text/html

# Invalidate CloudFront
aws cloudfront create-invalidation \
  --distribution-id DIST_ID \
  --paths "/index.html" "/asset-manifest.json"
```

Repeat for each app bucket.

---

## API (SSM + EC2)

### Auto-Rollback (Built In)

The SSM deploy document automatically rolls back if the health check fails:
1. After restart, 6 health checks at 5s intervals
2. If all fail, the `.old` directory is swapped back
3. Service is restarted with the previous version
4. The SSM command exits with failure → GHA reports failure → Slack notification

### Manual Rollback via Previous Tag (~2 min)

```bash
# Find the previous working tag
git tag --list 'stg-api-*' --sort=-v:refname | head -5

# Deploy via break-glass
# The artifact for the previous tag is still in S3 (90-day retention)
```

### Emergency: Direct SSM Rollback

If you need to rollback faster than a full deploy:

```bash
# On each instance, the .old directory contains the previous version
# This is only available immediately after a deploy (before the next one cleans it up)

aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --instance-ids "i-XXXXX" \
  --parameters 'commands=["rm -rf /var/www/triggr_api && mv /var/www/triggr_api.old /var/www/triggr_api && systemctl restart triggr-api"]'
```

---

## Mobile (EAS)

### OTA Update Rollback

For JavaScript-only changes:

```bash
# Push previous JS bundle as an OTA update
eas update --branch production --message "Rollback to previous version"
```

### Native Binary Rollback

Requires App Store / Play Store review. Prevention (thorough staging testing) is the primary strategy. Use the `preview` profile extensively before creating production builds.

---

## General Rollback Checklist

1. Identify the issue (logs, monitoring, user reports)
2. Determine rollback scope (which app/service, which environment)
3. Execute rollback using the appropriate method above
4. Verify rollback succeeded (health checks, manual testing)
5. Notify team via Slack (#ops)
6. Create a post-incident ticket
7. Investigate root cause before re-deploying the fix
