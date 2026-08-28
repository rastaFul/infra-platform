#!/usr/bin/env bash
# backup.sh — Local backup of all real data (SQLite DBs, Postgres, Docker
# volumes, Vault keys). Runs entirely local, zero cost. Remote upload to
# Cloudflare R2 is OPTIONAL and OFF by default — only activates if
# R2_* env vars are set (see docs/how-to/setup-r2-backup-destination.md).
# See infra-platform .specs/features/backup-strategy/spec.md.
#
# Usage: ./backup.sh
# Cron (daily, 3am): 0 3 * * * /home/rodrigo/projects/infra-platform/scripts/backup.sh >> ~/backups/rastaful/backup.log 2>&1

set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-${HOME}/backups/rastaful}"
DATE="$(date +%Y-%m-%d)"
DAY_OF_WEEK="$(date +%u)"  # 1=Monday
DAILY_DIR="${BACKUP_ROOT}/daily/${DATE}"
WEEKLY_DIR="${BACKUP_ROOT}/weekly/${DATE}"
RETENTION_DAILY_DAYS="${RETENTION_DAILY_DAYS:-7}"
RETENTION_WEEKLY_COUNT="${RETENTION_WEEKLY_COUNT:-4}"

log()  { echo "[backup] $(date -Iseconds) $*"; }
warn() { echo "[backup] WARN: $*" >&2; }

mkdir -p "${DAILY_DIR}"

# ── SQLite (via Python's sqlite3 module — safe hot-backup, same semantics
#    as `sqlite3 .backup`, avoids corrupting a file the app has open).
#    sqlite3 CLI isn't installed on this machine; Python's stdlib module
#    does the exact same thing without needing to install anything. ────
backup_sqlite() {
  local name="$1" src="$2"
  if [ ! -f "${src}" ]; then
    warn "SQLite source not found, skipping: ${src}"
    return
  fi
  local dest="${DAILY_DIR}/${name}.db"
  python3 -c "
import sqlite3
src = sqlite3.connect('${src}')
dest = sqlite3.connect('${dest}')
src.backup(dest)
src.close()
dest.close()
"
  gzip -f "${dest}"
  log "SQLite backed up: ${name} -> ${dest}.gz"
}

# ── Postgres (via docker exec pg_dump — no host pg_dump needed) ────────
backup_postgres() {
  local name="$1" container="$2" db="$3" user="$4" compose_dir="$5" compose_service="$6"

  if [ "$(docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null || echo false)" != "true" ]; then
    log "${container} not running — starting it (needed for pg_dump; left running afterwards, the app needs it anyway)"
    ( cd "${compose_dir}" && docker compose -f docker-compose.dev.yml up -d "${compose_service}" ) || \
      { warn "Could not start ${container} — skipping Postgres backup for ${name}"; return; }
    sleep 5
  fi

  local dest="${DAILY_DIR}/${name}.sql"
  docker exec -e PGPASSWORD="${PGPASSWORD:-}" "${container}" pg_dump -U "${user}" "${db}" > "${dest}" 2>/dev/null || \
    { warn "pg_dump failed for ${name} (container: ${container}) — check container env/credentials"; return; }
  gzip -f "${dest}"
  log "Postgres backed up: ${name} -> ${dest}.gz"
}

# ── Docker named volumes (influx, glitchtip-db, grafana, vault) ────────
backup_volume() {
  local volume="$1"
  local dest="${DAILY_DIR}/${volume}.tar.gz"
  docker run --rm \
    -v "${volume}:/data:ro" \
    -v "${DAILY_DIR}:/backup" \
    alpine sh -c "tar czf /backup/$(basename "${dest}") -C /data ." || \
    { warn "Volume backup failed: ${volume}"; return; }
  log "Volume backed up: ${volume} -> ${dest}"
}

# ── Vault unseal key / root token (already local file, chmod 600) ──────
backup_vault_keys() {
  local src="${HOME}/.vault-init-local"
  if [ ! -f "${src}" ]; then
    warn "Vault init file not found: ${src} — skipping (Vault not initialized yet?)"
    return
  fi
  cp "${src}" "${DAILY_DIR}/vault-init-local.json"
  chmod 600 "${DAILY_DIR}/vault-init-local.json"
  log "Vault keys backed up (local copy only — also copy to your password manager manually, see spec)"
}

# ── Retention: prune daily backups older than N days ────────────────────
rotate_daily() {
  find "${BACKUP_ROOT}/daily" -maxdepth 1 -mindepth 1 -type d -mtime "+${RETENTION_DAILY_DAYS}" -exec rm -rf {} \; 2>/dev/null || true
  log "Pruned daily backups older than ${RETENTION_DAILY_DAYS} days"
}

# ── Weekly snapshot: copy Monday's daily backup into weekly/, prune old ─
rotate_weekly() {
  mkdir -p "${BACKUP_ROOT}/weekly"

  if [ "${DAY_OF_WEEK}" = "1" ]; then
    mkdir -p "${WEEKLY_DIR}"
    cp -r "${DAILY_DIR}/." "${WEEKLY_DIR}/"
    log "Weekly snapshot created: ${WEEKLY_DIR}"
  fi

  # Keep only the N most recent weekly snapshots. `find` on a dir that's
  # always guaranteed to exist now (mkdir -p above) — under `pipefail`, a
  # `find` failure on a *missing* dir used to poison this whole pipeline
  # even though `wc -l` itself succeeded (found running this for real
  # 2026-08-28: the script exited 1 right after pruning dailies, before
  # ever reaching upload_to_r2).
  local count
  count=$(find "${BACKUP_ROOT}/weekly" -maxdepth 1 -mindepth 1 -type d | wc -l)
  if [ "${count}" -gt "${RETENTION_WEEKLY_COUNT}" ]; then
    find "${BACKUP_ROOT}/weekly" -maxdepth 1 -mindepth 1 -type d | sort | head -n "$((count - RETENTION_WEEKLY_COUNT))" | xargs -r rm -rf
    log "Pruned old weekly snapshots (keeping ${RETENTION_WEEKLY_COUNT})"
  fi
}

# ── Remote upload — OPTIONAL, OFF by default. Only runs if R2 env vars
#    are set. Never fails the whole backup if R2 isn't configured or
#    unreachable — local backup already succeeded, that's the priority. ─
upload_to_r2() {
  if [ -z "${R2_ACCOUNT_ID:-}" ] || [ -z "${R2_ACCESS_KEY_ID:-}" ] || [ -z "${R2_SECRET_ACCESS_KEY:-}" ] || [ -z "${R2_BUCKET:-}" ]; then
    log "R2 not configured (R2_ACCOUNT_ID/R2_ACCESS_KEY_ID/R2_SECRET_ACCESS_KEY/R2_BUCKET unset) — backups stay local only. See docs/how-to/setup-r2-backup-destination.md when ready to activate."
    return
  fi
  if ! command -v aws >/dev/null 2>&1; then
    warn "R2 env vars are set but 'aws' CLI isn't installed — skipping upload. Install: pip3 install --user awscli"
    return
  fi
  log "Uploading ${DAILY_DIR} to R2 bucket ${R2_BUCKET} ..."
  AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}" \
  AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}" \
  aws s3 sync "${DAILY_DIR}" "s3://${R2_BUCKET}/daily/${DATE}/" \
    --endpoint-url "https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com" \
    --only-show-errors || warn "R2 upload failed — local backup is still safe, investigate separately"
  log "R2 upload complete."
}

main() {
  log "Starting backup — local root: ${BACKUP_ROOT}"

  backup_sqlite "rastafinancas" "/home/rodrigo/projects/rastafinancas/apps/api/data/rastafinancas.db"
  backup_sqlite "artists-booking" "/home/rodrigo/projects/artists-booking/apps/api/prisma/dev.db"
  backup_postgres "vetcare" "vetcare-postgres-1" "vetcare_dev" "vetcare" "/home/rodrigo/projects/vetcare" "postgres"

  backup_volume "platform_influx_data"
  backup_volume "platform_glitchtip_postgres_data"
  backup_volume "platform_grafana_data"
  backup_volume "platform_vault_data"

  backup_vault_keys

  rotate_daily
  rotate_weekly
  upload_to_r2

  local size
  size=$(du -sh "${DAILY_DIR}" 2>/dev/null | cut -f1)
  log "Backup complete. ${DAILY_DIR} (${size})"
}

main "$@"
