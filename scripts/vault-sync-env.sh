#!/usr/bin/env bash
# vault-sync-env.sh — Pull a project's secrets from Vault (KV v2, via
# AppRole) and write them into its real .env file.
#
# Design decision: apps still read from a plain .env at runtime (via each
# ecosystem.config.js's loadEnv() helper) — they do NOT depend on Vault
# being reachable to boot. Vault is the canonical secret store you sync
# FROM (on rotation, on new secret, on new machine); it is not a live
# runtime dependency. This is a deliberate simplification for this scale
# (personal projects, not an enterprise fleet) — see
# .specs/features/vault-secrets-migration/spec.md (or DECISIONS.md if no
# dedicated spec exists) for the reasoning.
#
# Usage: ./vault-sync-env.sh <project> <path-to-.env>
# Requires: ~/.vault-approle-<project>.json (chmod 600, NOT in git) with
#   {"role_id": "...", "secret_id": "..."}
# Generate that file once via: ./vault-generate-approle-creds.sh <project>

set -euo pipefail

PROJECT="${1:?Usage: vault-sync-env.sh <project> <path-to-.env>}"
ENV_FILE="${2:?Usage: vault-sync-env.sh <project> <path-to-.env>}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
CREDS_FILE="${HOME}/.vault-approle-${PROJECT}.json"

log()  { echo "[vault-sync-env:${PROJECT}] $*"; }
die()  { echo "[vault-sync-env:${PROJECT}] ERROR: $*" >&2; exit 1; }

[ -f "${CREDS_FILE}" ] || die "AppRole creds not found: ${CREDS_FILE}. Run vault-generate-approle-creds.sh ${PROJECT} first."
[ -f "${ENV_FILE}" ] || die "Target .env not found: ${ENV_FILE}"

ROLE_ID=$(python3 -c "import json; print(json.load(open('${CREDS_FILE}'))['role_id'])")
SECRET_ID=$(python3 -c "import json; print(json.load(open('${CREDS_FILE}'))['secret_id'])")

# ── Login via AppRole ────────────────────────────────────────────────
LOGIN_RESPONSE=$(curl -s -X POST "${VAULT_ADDR}/v1/auth/approle/login" \
  -d "{\"role_id\":\"${ROLE_ID}\",\"secret_id\":\"${SECRET_ID}\"}")
VAULT_TOKEN=$(echo "${LOGIN_RESPONSE}" | python3 -c "import json,sys; print(json.load(sys.stdin)['auth']['client_token'])" 2>/dev/null) || \
  die "AppRole login failed. Response: ${LOGIN_RESPONSE}"

# ── Fetch secret (KV v2: data lives under .data.data) ───────────────
# Written to a temp file, never interpolated as a bash string — secret
# values can contain $, `, \, ' etc. which bash mangles when substituted
# into a heredoc (found running this for real 2026-08-28: broke silently
# for 2 of 4 projects whose secrets happened to contain such characters,
# the other 2 "passed" only because their secrets were plain enough to
# not trigger it — a correctness bug, not a syntax error, the dangerous
# kind).
SECRET_RESPONSE_FILE=$(mktemp)
trap 'rm -f "${SECRET_RESPONSE_FILE}"' EXIT
curl -s -H "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/secret/data/${PROJECT}/env" > "${SECRET_RESPONSE_FILE}"

HAS_DATA=$(python3 -c "import json; d=json.load(open('${SECRET_RESPONSE_FILE}')); print('yes' if d.get('data',{}).get('data') else 'no')" 2>/dev/null || echo "no")
[ "${HAS_DATA}" = "yes" ] || die "No secret found at secret/data/${PROJECT}/env — run the migration push first."

# ── Merge into .env: overwrite keys that exist in Vault, keep any local-
#    only keys (e.g. NODE_ENV, PORT if not managed in Vault) untouched ──
python3 - "${ENV_FILE}" "${SECRET_RESPONSE_FILE}" <<'PYEOF'
import json, re, sys

env_file = sys.argv[1]
secret_response_file = sys.argv[2]
with open(secret_response_file) as f:
    vault_data = json.load(f)['data']['data']

# Parse existing .env, preserving comments/order for keys not in Vault
lines = []
try:
    with open(env_file) as f:
        lines = f.readlines()
except FileNotFoundError:
    lines = []

existing_keys = set()
new_lines = []
for line in lines:
    stripped = line.strip()
    if not stripped or stripped.startswith('#') or '=' not in stripped:
        new_lines.append(line)
        continue
    key = stripped.split('=', 1)[0].strip()
    if key in vault_data:
        new_lines.append(f"{key}={vault_data[key]}\n")
        existing_keys.add(key)
    else:
        new_lines.append(line)
        existing_keys.add(key)

# Append any Vault keys not already present in the file
missing = [k for k in vault_data if k not in existing_keys]
if missing:
    new_lines.append("\n# Synced from Vault (vault-sync-env.sh)\n")
    for k in missing:
        new_lines.append(f"{k}={vault_data[k]}\n")

with open(env_file, 'w') as f:
    f.writelines(new_lines)

print(f"Synced {len(vault_data)} keys from Vault into {env_file}")
PYEOF

log "Sync complete."
