#!/usr/bin/env bash
# vault-generate-approle-creds.sh — Generate role_id + secret_id for a
# project's AppRole (created by vault-init.sh) and save locally.
#
# Usage: ./vault-generate-approle-creds.sh <project>
# Requires: ~/.vault-init-local (root token, from vault-init.sh)
# Writes: ~/.vault-approle-<project>.json (chmod 600, NOT in git)

set -euo pipefail

PROJECT="${1:?Usage: vault-generate-approle-creds.sh <project>}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_INIT_FILE="${HOME}/.vault-init-local"
CREDS_FILE="${HOME}/.vault-approle-${PROJECT}.json"

log() { echo "[vault-generate-approle-creds:${PROJECT}] $*"; }
die() { echo "[vault-generate-approle-creds:${PROJECT}] ERROR: $*" >&2; exit 1; }

[ -f "${VAULT_INIT_FILE}" ] || die "${VAULT_INIT_FILE} not found — Vault not initialized? Run vault-init.sh first."

ROOT_TOKEN=$(python3 -c "import json; print(json.load(open('${VAULT_INIT_FILE}'))['root_token'])")

ROLE_ID=$(curl -s -H "X-Vault-Token: ${ROOT_TOKEN}" \
  "${VAULT_ADDR}/v1/auth/approle/role/${PROJECT}/role-id" | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['data']['role_id'])") || \
  die "Could not fetch role_id — does AppRole '${PROJECT}' exist? (should have been created by vault-init.sh)"

SECRET_ID=$(curl -s -X POST -H "X-Vault-Token: ${ROOT_TOKEN}" \
  "${VAULT_ADDR}/v1/auth/approle/role/${PROJECT}/secret-id" | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['data']['secret_id'])") || \
  die "Could not generate secret_id"

python3 -c "
import json
with open('${CREDS_FILE}', 'w') as f:
    json.dump({'role_id': '${ROLE_ID}', 'secret_id': '${SECRET_ID}'}, f)
"
chmod 600 "${CREDS_FILE}"
log "Credentials saved to ${CREDS_FILE} (chmod 600, never printed to stdout)"
