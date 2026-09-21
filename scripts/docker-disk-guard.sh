#!/usr/bin/env bash
# docker-disk-guard.sh — Prevents a repeat of the 2026-09-21 incident (C: drive
# at 9.1GB/477GB free because docker_data.vhdx grew to 88GB unnoticed).
#
# Does 3 things, in order:
#   1. Safe prune (dangling images + build cache only — never touches a tagged
#      image or a volume).
#   2. Threshold check: WARNs if docker_data.vhdx is too big or C: free space
#      is too low. Does NOT compact the vhdx itself — that needs Admin
#      elevation and was proven unreliable to automate unattended on
#      2026-09-21 (file-lock even with Docker Desktop fully stopped). See
#      docs/how-to/docker-disk-cleanup.md for the manual procedure.
#   3. Flags (never deletes) tagged images that look like manual rollback/
#      backup images (*-rollback, *-pre-*) older than RETENTION_ROLLBACK_DAYS
#      — deleting those is always a human decision.
#
# See .specs/features/docker-disk-lifecycle/spec.md (D1-D5) for the reasoning
# behind every threshold/decision below.
#
# Usage: ./docker-disk-guard.sh
# Cron (daily, 35min after the 3am backup.sh to avoid I/O contention):
#   35 3 * * * /home/rodrigo/projects/infra-platform/scripts/docker-disk-guard.sh >> ~/logs/docker-disk-guard.log 2>&1

set -euo pipefail

VHDX_PATH="${VHDX_PATH:-/mnt/c/Users/rodri/AppData/Local/Docker/wsl/disk/docker_data.vhdx}"
VHDX_WARN_GB="${VHDX_WARN_GB:-40}"
C_DRIVE_FREE_WARN_GB="${C_DRIVE_FREE_WARN_GB:-20}"
RETENTION_ROLLBACK_DAYS="${RETENTION_ROLLBACK_DAYS:-14}"

log()  { echo "[docker-disk-guard] $(date -Iseconds) $*"; }
warn() { echo "[docker-disk-guard] $(date -Iseconds) WARN: $*" >&2; }

if ! docker version >/dev/null 2>&1; then
  warn "Docker daemon not reachable — skipping this run (Docker Desktop likely stopped)."
  exit 0
fi

log "Starting safe prune (dangling images + build cache only)..."
IMG_PRUNE_OUT="$(docker image prune -f 2>&1)"
BUILD_PRUNE_OUT="$(docker builder prune -af 2>&1)"
log "image prune: $(echo "${IMG_PRUNE_OUT}" | tail -1)"
log "builder prune: $(echo "${BUILD_PRUNE_OUT}" | tail -1)"

# ── Threshold check ─────────────────────────────────────────────────────
if [ -f "${VHDX_PATH}" ]; then
  VHDX_BYTES="$(stat -c %s "${VHDX_PATH}")"
  VHDX_GB="$(( VHDX_BYTES / 1024 / 1024 / 1024 ))"
  log "docker_data.vhdx size: ${VHDX_GB}GB (warn threshold: ${VHDX_WARN_GB}GB)"
  if [ "${VHDX_GB}" -ge "${VHDX_WARN_GB}" ]; then
    warn "docker_data.vhdx is ${VHDX_GB}GB (>= ${VHDX_WARN_GB}GB threshold)." \
         "Run the manual compaction procedure: docs/how-to/docker-disk-cleanup.md"
  fi
else
  warn "vhdx not found at ${VHDX_PATH} (path may differ on this machine — check VHDX_PATH env var)."
fi

C_FREE_GB="$(df --output=avail -BG /mnt/c 2>/dev/null | tail -1 | tr -dc '0-9')"
if [ -n "${C_FREE_GB}" ]; then
  log "C: free space: ${C_FREE_GB}GB (warn threshold: ${C_DRIVE_FREE_WARN_GB}GB)"
  if [ "${C_FREE_GB}" -le "${C_DRIVE_FREE_WARN_GB}" ]; then
    warn "C: drive down to ${C_FREE_GB}GB free (<= ${C_DRIVE_FREE_WARN_GB}GB threshold)." \
         "Run the manual compaction procedure: docs/how-to/docker-disk-cleanup.md"
  fi
else
  warn "could not read C: free space (df /mnt/c failed — is this running inside WSL2?)."
fi

# ── Rollback/backup tag flagging (never auto-deleted) ───────────────────
log "Scanning for rollback/backup-tagged images older than ${RETENTION_ROLLBACK_DAYS} days..."
CUTOFF_EPOCH="$(date -d "-${RETENTION_ROLLBACK_DAYS} days" +%s)"
FLAGGED=0
while IFS=$'\t' read -r repo_tag created_at; do
  [ -z "${repo_tag}" ] && continue
  case "${repo_tag}" in
    *-rollback*|*-pre-*)
      created_epoch="$(date -d "${created_at}" +%s 2>/dev/null || echo 0)"
      if [ "${created_epoch}" -gt 0 ] && [ "${created_epoch}" -lt "${CUTOFF_EPOCH}" ]; then
        warn "rollback-tagged image older than ${RETENTION_ROLLBACK_DAYS}d, review for manual removal: ${repo_tag} (created ${created_at})"
        FLAGGED=$((FLAGGED + 1))
      fi
      ;;
  esac
done < <(docker images --format '{{.Repository}}:{{.Tag}}	{{.CreatedAt}}' 2>/dev/null || true)
log "Rollback-tag scan done: ${FLAGGED} flagged (not deleted — manual decision required)."

log "docker-disk-guard run complete."
