#!/usr/bin/env bash
# vault-init.sh — Idempotent Vault initialization for local platform
# Saves unseal keys to ~/.vault-init-local (NOT tracked by git)
# Run after: docker compose up -d (vault must be healthy)
#
# Mode auto-detection:
#   - If 'vault' CLI is installed locally: uses it directly
#   - Otherwise: runs vault commands via 'docker exec platform-vault vault'

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_CONTAINER="${VAULT_CONTAINER:-platform-vault}"
VAULT_INIT_FILE="${HOME}/.vault-init-local"
# "platform" added 2026-09-15 (infra-full-upgrade-2026-09-followups T2) --
# not a product, the shared observability/secrets stack itself. Same
# apply_policy/create_approle treatment as the 4 real tenants.
PROJECTS=(vetcare rastafinancas microgrow artists platform)

export VAULT_ADDR

log()  { echo "[vault-init] $*"; }
warn() { echo "[vault-init] WARN: $*" >&2; }
die()  { echo "[vault-init] ERROR: $*" >&2; exit 1; }

# ── Vault CLI wrapper (local or via docker exec) ──────────────────────────────
vault_cmd() {
  if command -v vault >/dev/null 2>&1; then
    VAULT_ADDR="${VAULT_ADDR}" VAULT_TOKEN="${VAULT_TOKEN:-}" vault "$@"
  else
    docker exec \
      -e VAULT_ADDR="http://localhost:8200" \
      -e VAULT_TOKEN="${VAULT_TOKEN:-}" \
      "${VAULT_CONTAINER}" vault "$@"
  fi
}

# ── Wait for Vault to be reachable (via HTTP — no CLI needed) ─────────────────
wait_for_vault() {
  log "Waiting for Vault at ${VAULT_ADDR} ..."
  local attempts=0
  # NOTE: no `-f` here on purpose. Vault's /v1/sys/health intentionally
  # returns non-2xx codes for valid states (501 not initialized, 503
  # sealed, 429 standby) — `curl -f` treats those as failures and never
  # sees the body, so this loop always timed out even when Vault was
  # perfectly reachable (found running this for real 2026-08-28). We only
  # care that curl got *a* JSON response with an "initialized" key, not
  # the HTTP status code.
  until curl -s "${VAULT_ADDR}/v1/sys/health" 2>/dev/null | grep -q '"initialized"'; do
    sleep 2
    attempts=$((attempts + 1))
    [ $attempts -ge 30 ] && die "Vault did not become reachable after 60s. Is it running?"
  done
  log "Vault reachable."
}

# ── Initialize Vault (once) ──────────────────────────────────────────────────
init_vault() {
  local init_status
  init_status=$( curl -s "${VAULT_ADDR}/v1/sys/health" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(str(d['initialized']).lower())" 2>/dev/null || echo "false")

  if [ "${init_status}" = "true" ]; then
    log "Vault already initialized — skipping init."
    return
  fi

  log "Initializing Vault (1 key share, threshold 1) ..."
  vault_cmd operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > "${VAULT_INIT_FILE}"

  chmod 600 "${VAULT_INIT_FILE}"
  log "Init complete. Keys saved to ${VAULT_INIT_FILE} (chmod 600)."
  warn "KEEP ${VAULT_INIT_FILE} SAFE — it contains the unseal key and root token."
}

# ── Unseal Vault ─────────────────────────────────────────────────────────────
unseal_vault() {
  local sealed
  sealed=$( curl -s "${VAULT_ADDR}/v1/sys/health" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(str(d['sealed']).lower())" 2>/dev/null || echo "true")

  if [ "${sealed}" = "false" ]; then
    log "Vault already unsealed."
    return
  fi

  if [ ! -f "${VAULT_INIT_FILE}" ]; then
    die "Vault is sealed but ${VAULT_INIT_FILE} not found. Cannot unseal automatically."
  fi

  local unseal_key
  unseal_key=$(python3 -c "import json; d=json.load(open('${VAULT_INIT_FILE}')); print(d['unseal_keys_b64'][0])")

  log "Unsealing Vault ..."
  vault_cmd operator unseal "${unseal_key}"
  log "Vault unsealed."
}

# ── Authenticate as root ─────────────────────────────────────────────────────
auth_root() {
  VAULT_TOKEN=$(python3 -c "import json; d=json.load(open('${VAULT_INIT_FILE}')); print(d['root_token'])")
  export VAULT_TOKEN
  log "Authenticated with root token."
}

# ── Enable KV v2 ─────────────────────────────────────────────────────────────
enable_kv() {
  if vault_cmd secrets list -format=json 2>/dev/null | python3 -c \
      "import sys,json; d=json.load(sys.stdin); print('ok' if 'secret/' in d else 'missing')" 2>/dev/null | grep -q "^ok$"; then
    log "KV v2 engine already enabled at secret/."
    return
  fi
  log "Enabling KV v2 secrets engine at secret/ ..."
  vault_cmd secrets enable -path=secret kv-v2
  log "KV v2 enabled."
}

# ── Enable AppRole auth ───────────────────────────────────────────────────────
enable_approle() {
  if vault_cmd auth list -format=json 2>/dev/null | python3 -c \
      "import sys,json; d=json.load(sys.stdin); print('ok' if 'approle/' in d else 'missing')" 2>/dev/null | grep -q "^ok$"; then
    log "AppRole auth already enabled."
    return
  fi
  log "Enabling AppRole auth method ..."
  vault_cmd auth enable approle
  log "AppRole enabled."
}

# ── Apply policy via file (copy to container if needed) ───────────────────────
apply_policy() {
  local project="$1"
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  local policy_path="${script_dir}/../platform/vault/policies/${project}.hcl"

  if [ ! -f "${policy_path}" ]; then
    warn "Policy file not found: ${policy_path} — skipping."
    return
  fi

  log "Applying policy: ${project} ..."
  if command -v vault >/dev/null 2>&1; then
    vault_cmd policy write "${project}" "${policy_path}"
  else
    # Copy policy into container then apply
    docker cp "${policy_path}" "${VAULT_CONTAINER}:/tmp/${project}.hcl"
    docker exec \
      -e VAULT_ADDR="http://localhost:8200" \
      -e VAULT_TOKEN="${VAULT_TOKEN}" \
      "${VAULT_CONTAINER}" vault policy write "${project}" "/tmp/${project}.hcl"
  fi
}

# ── Create AppRole per project ────────────────────────────────────────────────
create_approle() {
  local project="$1"

  if vault_cmd read -format=json "auth/approle/role/${project}" >/dev/null 2>&1; then
    log "AppRole '${project}' already exists — skipping creation."
  else
    log "Creating AppRole for: ${project} ..."
    vault_cmd write "auth/approle/role/${project}" \
      policies="${project}" \
      token_ttl=1h \
      token_max_ttl=4h \
      secret_id_ttl=0
  fi

  local role_id secret_id
  role_id=$(vault_cmd read -format=json "auth/approle/role/${project}/role-id" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['role_id'])")
  secret_id=$(vault_cmd write -format=json -f "auth/approle/role/${project}/secret-id" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['secret_id'])")

  echo ""
  echo "  ┌─ ${project} ────────────────────────────────────────────"
  echo "  │  role_id:   ${role_id}"
  echo "  │  secret_id: ${secret_id}"
  echo "  └────────────────────────────────────────────────────────"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  log "Starting Vault initialization sequence ..."
  log "Mode: $(command -v vault >/dev/null 2>&1 && echo 'local vault CLI' || echo "docker exec ${VAULT_CONTAINER}")"

  wait_for_vault
  init_vault
  unseal_vault
  auth_root
  enable_kv
  enable_approle

  log "Applying policies and creating AppRoles for all projects ..."
  for project in "${PROJECTS[@]}"; do
    apply_policy "${project}"
    create_approle "${project}"
  done

  log "Vault init complete."
  echo ""
  echo "  Vault UI: ${VAULT_ADDR}/ui"
  echo "  Root token: $(python3 -c "import json; d=json.load(open('${VAULT_INIT_FILE}')); print(d['root_token'])")"
  echo ""
  warn "Rotate root token in production: vault token revoke -self"
}

main "$@"
