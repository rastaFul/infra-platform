# How to Restore from Backup

See `scripts/backup.sh` and `.specs/features/backup-strategy/spec.md`. Backups live at `~/backups/rastaful/daily/<date>/` (local, override with `BACKUP_ROOT` env var).

Restore procedure below was validated for real on 2026-08-28 (SQLite path) — same size, same tables recovered.

## SQLite (rastafinancas, artists-booking)

```bash
gunzip -c ~/backups/rastaful/daily/<date>/rastafinancas.db.gz > /tmp/restored.db
# Verify before replacing the real file:
python3 -c "
import sqlite3
conn = sqlite3.connect('/tmp/restored.db')
print([r[0] for r in conn.execute(\"SELECT name FROM sqlite_master WHERE type='table'\")])
"
# Only after verifying: stop the app (pm2 stop rastafinancas-api), replace the file, restart
pm2 stop rastafinancas-api
cp /tmp/restored.db /home/rodrigo/projects/rastafinancas/apps/api/data/rastafinancas.db
pm2 start rastafinancas-api
```

Same pattern for artists-booking, target path `apps/api/prisma/dev.db`.

## Postgres (vetcare)

```bash
gunzip -c ~/backups/rastaful/daily/<date>/vetcare.sql.gz > /tmp/restored.sql
# Restore into a FRESH database first to verify, never straight into prod:
docker exec -i vetcare-postgres-1 psql -U vetcare -c "CREATE DATABASE vetcare_restore_test;"
docker exec -i vetcare-postgres-1 psql -U vetcare vetcare_restore_test < /tmp/restored.sql
# Verify row counts / spot-check data, THEN if good:
pm2 stop vetcare
docker exec -i vetcare-postgres-1 psql -U vetcare -c "DROP DATABASE vetcare_dev;"
docker exec -i vetcare-postgres-1 psql -U vetcare -c "ALTER DATABASE vetcare_restore_test RENAME TO vetcare_dev;"
pm2 start vetcare
```

## Docker volumes (InfluxDB, GlitchTip, Grafana, Vault)

```bash
# Example: restore platform_influx_data into a NEW volume first, verify, then swap
docker volume create platform_influx_data_restore_test
docker run --rm \
  -v platform_influx_data_restore_test:/data \
  -v ~/backups/rastaful/daily/<date>:/backup \
  alpine sh -c "cd /data && tar xzf /backup/platform_influx_data.tar.gz"

# To actually swap it in (only after verifying), edit
# infra-platform/platform/docker-compose.yml's volume `name:` temporarily,
# or rename volumes via `docker volume` — there's no direct rename command,
# safest is: stop the stack, `docker volume rm platform_influx_data`,
# then rename the restored one by recreating with the original name and
# copying data across (same tar-based approach, reversed).
```

## Vault unseal keys

```bash
cp ~/backups/rastaful/daily/<date>/vault-init-local.json ~/.vault-init-local
chmod 600 ~/.vault-init-local
```

Restores Vault's unseal key + root token — needed if `~/.vault-init-local` is ever lost (Vault itself would need re-init from scratch otherwise, losing all stored secrets).

## Restore drill cadence

Test at least the SQLite path every time you touch `backup.sh`. Full drill (Postgres + volumes) recommended quarterly — a backup that's never been restored is a hope, not a backup.
