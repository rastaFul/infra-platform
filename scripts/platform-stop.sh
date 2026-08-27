#!/usr/bin/env bash
# platform-stop.sh — Stop platform stack in reverse order

set -euo pipefail

SERVICES_PLATFORM_DIR="${HOME}/projects/services/platform"
INFRA_PLATFORM_DIR="${HOME}/projects/infra-platform/platform"

log() { echo "[platform-stop] $*"; }

log "Stopping infra-platform/platform (Vault, OTEL Collector) ..."
docker compose --project-directory "${INFRA_PLATFORM_DIR}" down

log "Stopping services/platform (Grafana, InfluxDB, Loki, GlitchTip) ..."
docker compose --project-directory "${SERVICES_PLATFORM_DIR}" down

log "Platform stack stopped."
