# How to Activate Cloudflare R2 as the Backup Destination

**Status: NOT activated on purpose.** `backup.sh` already runs daily, local-only, zero cost (see `.specs/features/backup-strategy/spec.md`, D3). This doc is for when you're ready to add off-machine redundancy — it requires enabling billing on your Cloudflare account (R2 needs a payment method on file even to use the free tier, as of this writing), which is exactly the kind of step the agent won't take on your behalf. Do this yourself when ready.

## 1. Enable R2 on Cloudflare

1. Cloudflare dashboard → R2 → enable (requires adding a payment method — free tier: 10GB storage, 1M Class A + 10M Class B ops/month, no charge within those limits)
2. Create a bucket, e.g. `rastaful-backups`

## 2. Create an API token scoped to R2 only

Dashboard → R2 → Manage R2 API Tokens → Create API Token. Scope: **Object Read & Write**, restrict to the one bucket. Note down:
- Access Key ID
- Secret Access Key
- Account ID (top-right of the R2 dashboard, or `https://dash.cloudflare.com/<account-id>/r2`)

## 3. Install the AWS CLI (R2 is S3-compatible)

```bash
pip3 install --user awscli
```

## 4. Set the env vars `backup.sh` already checks for

Add to `~/.zshrc` (or a dedicated `~/.backup-env` sourced from the cron entry — don't put real credentials in a file that could accidentally get committed):

```bash
export R2_ACCOUNT_ID="your-account-id"
export R2_ACCESS_KEY_ID="your-access-key-id"
export R2_SECRET_ACCESS_KEY="your-secret-access-key"
export R2_BUCKET="rastaful-backups"
```

## 5. Verify

```bash
/home/rodrigo/projects/infra-platform/scripts/backup.sh
```

Look for `Uploading ... to R2 bucket ... / R2 upload complete.` in the log instead of the "R2 not configured" message. No code changes needed — the script already has the upload logic, it's dormant until these 4 env vars exist.

## 6. Update the cron entry to load the env vars

The crontab entry runs in a minimal environment (doesn't source `~/.zshrc`). Either:
- Move the `export R2_*` lines into a file the cron job sources first, or
- Add them directly to the crontab entry: `R2_ACCOUNT_ID=... R2_ACCESS_KEY_ID=... 0 3 * * * /home/rodrigo/projects/infra-platform/scripts/backup.sh ...`
