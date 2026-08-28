#!/usr/bin/env bash
# vault-push-env.sh — One-time migration: read a project's real .env and
# push it into Vault KV v2 (secret/data/<project>/env). Run once per
# project to seed Vault, then vault-sync-env.sh pulls it back on any
# machine/rotation.
#
# Usage: ./vault-push-env.sh <project> <path-to-.env>
# Requires: ~/.vault-init-local (root token)

set -euo pipefail

PROJECT="${1:?Usage: vault-push-env.sh <project> <path-to-.env>}"
ENV_FILE="${2:?Usage: vault-push-env.sh <project> <path-to-.env>}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_INIT_FILE="${HOME}/.vault-init-local"

log() { echo "[vault-push-env:${PROJECT}] $*"; }
die() { echo "[vault-push-env:${PROJECT}] ERROR: $*" >&2; exit 1; }

[ -f "${VAULT_INIT_FILE}" ] || die "${VAULT_INIT_FILE} not found"
[ -f "${ENV_FILE}" ] || die "${ENV_FILE} not found"

ROOT_TOKEN=$(python3 -c "import json; print(json.load(open('${VAULT_INIT_FILE}'))['root_token'])")

PAYLOAD=$(python3 - "${ENV_FILE}" <<'PYEOF'
import json, sys

env_file = sys.argv[1]
data = {}
with open(env_file) as f:
    for line in f:
        stripped = line.strip()
        if not stripped or stripped.startswith('#') or '=' not in stripped:
            continue
        key, _, value = stripped.partition('=')
        data[key.strip()] = value.strip()

print(json.dumps({"data": data}))
PYEOF
)

KEY_COUNT=$(echo "${PAYLOAD}" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))")

curl -s -X POST -H "X-Vault-Token: ${ROOT_TOKEN}" \
  -d "${PAYLOAD}" \
  "${VAULT_ADDR}/v1/secret/data/${PROJECT}/env" > /tmp/vault-push-response.json

if python3 -c "import json; d=json.load(open('/tmp/vault-push-response.json')); exit(0 if 'errors' not in d else 1)" 2>/dev/null; then
  log "Pushed ${KEY_COUNT} keys to secret/data/${PROJECT}/env"
else
  die "Push failed: $(cat /tmp/vault-push-response.json)"
fi
rm -f /tmp/vault-push-response.json
