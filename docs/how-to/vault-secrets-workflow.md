# Vault Secrets Workflow

Migrated 2026-08-28 — all 4 projects' real secrets now live in Vault KV v2 (`secret/data/<project>/env`), pushed via AppRole created by `vault-init.sh`.

## Design decision: Vault is canonical, `.env` is what apps actually read

Apps do **not** fetch secrets from Vault at boot. They keep reading a plain `.env` file exactly as before (via each `ecosystem.config.js`'s `loadEnv()` helper) — zero app code changes, zero new runtime dependency on Vault being reachable to start a process.

Vault is the **source of truth you sync from** — on a new machine, after rotating a secret, or when re-provisioning. `.env` is a synced copy, not hand-maintained truth anymore.

```
Vault (secret/data/<project>/env)
   │
   │  vault-sync-env.sh <project> <path-to-.env>   (pull — read-only, safe to run anytime)
   ▼
apps/api/.env  ← what the app (via ecosystem.config.js) actually reads
```

This is a deliberate simplification for this scale (personal projects, single operator) — not "real" dynamic secrets (short-lived credentials fetched per-request). If/when that's warranted, it's a different, bigger change to each app's bootstrap code — not done here.

## Scripts

| Script | Purpose | When to run |
|---|---|---|
| `vault-generate-approle-creds.sh <project>` | Generate `role_id`+`secret_id` for a project, save to `~/.vault-approle-<project>.json` (chmod 600, never in git) | Once per machine, or if creds need rotating |
| `vault-push-env.sh <project> <path-to-.env>` | **One-time migration**: read a real `.env`, push all keys into Vault | Once, already done for all 4 projects (2026-08-28). Re-run only if you add/change a secret and want Vault to reflect it |
| `vault-sync-env.sh <project> <path-to-.env>` | Pull secrets from Vault, write into `.env` (merges — keys not in Vault are left untouched) | On a new machine, after rotating a secret in Vault, or to verify `.env` matches Vault |

## Rotating a secret

1. Update the value in Vault directly (UI at `http://127.0.0.1:8200/ui`, or `vault kv put secret/<project>/env <key>=<new-value>` — careful, this is a full overwrite of the KV v2 version unless you read-modify-write; safer via UI for a single key)
2. `./vault-sync-env.sh <project> <path-to-.env>`
3. Restart the app: `pm2 start ecosystem.config.js --only <app-name>`

## New machine (e.g. Oracle VM later, ADR 007)

1. Copy `~/.vault-init-local` (root token — or better, a scoped token) and the relevant `~/.vault-approle-<project>.json` files over **out of band** (never via git, never via a channel that gets logged) — e.g. via the backup restore procedure (`docs/how-to/restore-from-backup.md`) or manually.
2. `./vault-sync-env.sh <project> <path-to-.env>` for each project.

## Real bug found building this (2026-08-28)

`vault-sync-env.sh` originally embedded Vault's JSON response directly into a bash heredoc (`<<PYEOF ... '''${SECRET_RESPONSE}''' ... PYEOF`, unquoted delimiter). Bash re-parses unquoted heredoc content for `$`, backticks, etc. — any secret value containing those characters got silently mangled before Python ever saw it. Broke for 2 of the 4 projects (whichever had such characters in a real secret) on the first real run; the other 2 "passed" only because their values happened to be simple enough. Fixed by writing the response to a temp file and using a quoted heredoc delimiter (`<<'PYEOF'`) so bash never touches the Python source or the secret content. Re-validated: all 4 projects round-trip byte-identical to their pre-migration `.env`.
