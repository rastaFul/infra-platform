#!/usr/bin/env bash
# platform-start.sh — Start full platform stack in correct order
# 1. services/platform (Grafana, InfluxDB, Loki, GlitchTip)
# 2. infra-platform/platform (Vault, OTEL Collector)
# 3. vault-init.sh (idempotent)

set -euo pipefail

SERVICES_PLATFORM_DIR="${HOME}/projects/services/platform"
INFRA_PLATFORM_DIR="${HOME}/projects/infra-platform/platform"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log()  { echo "[platform-start] $*"; }
die()  { echo "[platform-start] ERROR: $*" >&2; exit 1; }

wait_healthy() {
  local name="$1"
  local check_cmd="$2"
  local attempts=0
  log "Waiting for ${name} to be healthy ..."
  until eval "${check_cmd}" >/dev/null 2>&1; do
    sleep 3
    attempts=$((attempts + 1))
    if [ $attempts -ge 40 ]; then
      die "${name} did not become healthy after 120s."
    fi
  done
  log "${name} is healthy."
}

# ── Step 1: Start services/platform ─────────────────────────────────────────
log "Step 1/3 — Starting services/platform (Grafana, InfluxDB, Loki, GlitchTip) ..."

if [ ! -f "${SERVICES_PLATFORM_DIR}/.env" ]; then
  die ".env not found at ${SERVICES_PLATFORM_DIR}/.env — copy .env.example and fill in values."
fi

docker compose --project-directory "${SERVICES_PLATFORM_DIR}" \
  --env-file "${SERVICES_PLATFORM_DIR}/.env" \
  up -d

wait_healthy "Loki"    "curl -sf http://localhost:3100/ready"
wait_healthy "Grafana" "curl -sf http://localhost:3010/api/health"

log "services/platform is up."

# ── Step 2: Start infra-platform/platform ────────────────────────────────────
log "Step 2/3 — Starting infra-platform/platform (Vault, OTEL Collector) ..."

ENV_FILE="${INFRA_PLATFORM_DIR}/../.env"
if [ -f "${ENV_FILE}" ]; then
  ENV_ARGS="--env-file ${ENV_FILE}"
else
  ENV_ARGS=""
  log "No .env found at ${INFRA_PLATFORM_DIR}/../.env — starting without env file."
fi

docker compose --project-directory "${INFRA_PLATFORM_DIR}" \
  ${ENV_ARGS} \
  up -d

wait_healthy "Vault" "curl -sf ${VAULT_ADDR}/v1/sys/health"
wait_healthy "OTEL Collector" "curl -sf http://localhost:8888/metrics"

log "infra-platform/platform is up."

# ── Step 3: Initialize Vault (idempotent) ────────────────────────────────────
log "Step 3/3 — Running vault-init.sh ..."
"${SCRIPT_DIR}/vault-init.sh"

# ── Final status ─────────────────────────────────────────────────────────────
echo ""
echo "Platform stack running:"
echo "  Grafana:        http://localhost:3010"
echo "  InfluxDB:       http://localhost:8086"
echo "  Loki:           http://localhost:3100"
echo "  GlitchTip:      http://localhost:8010"
echo "  Vault:          http://localhost:8200"
echo "  OTEL Collector: grpc://localhost:4317  http://localhost:4318"
echo "  OTEL Metrics:   http://localhost:8888/metrics"
echo ""
docker compose --project-directory "${SERVICES_PLATFORM_DIR}" ps
docker compose --project-directory "${INFRA_PLATFORM_DIR}" ps
