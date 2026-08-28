# SPEC: Backup Strategy

## Status: DRAFT
## Created: 2026-08-27
## Owner: rodrigo

---

## Contexto

Pain point identificado desde a spec original (`features/infra-strategy/spec.md`, 2026-08-12, item 14): "No backup strategy — SQLite DBs not backed up. InfluxDB/Postgres volumes not snapshotted." Nunca resolvido. Reforçado pela consolidação de hoje (ADR 010) — achamos 3 gerações de volumes órfãos por renomes de pasta; sem backup, um erro de operação (não renome, mas um `docker volume rm` errado, disco corrompido, etc.) teria sido perda permanente de dado real (142MB InfluxDB, 155MB GlitchTip, dados financeiros do rastafinancas).

## O que precisa de backup

| Dado | Onde vive hoje | Criticidade |
|---|---|---|
| rastafinancas SQLite | `apps/api/data/rastafinancas.db` (arquivo local) | ALTA — dado financeiro pessoal |
| artists-booking SQLite (Prisma) | arquivo local | MÉDIA |
| vetcare Postgres | volume Docker `vetcare_postgres_dev_data` | MÉDIA |
| InfluxDB (microgrow sensores) | volume `platform_influx_data` | BAIXA-MÉDIA (recriável via simulador, mas histórico real se perde) |
| GlitchTip Postgres (erros) | volume `platform_glitchtip_postgres_data` | BAIXA (histórico de erros, não crítico) |
| Grafana (dashboards/config) | volume `platform_grafana_data` | BAIXA (dashboards são provisionados via arquivo, recriável) |
| Vault (quando inicializado) | volume `platform_vault_data` | **ALTA** — unseal keys/secrets, perda = todo secret perdido |

## Done Criteria

1. Script de backup automatizado (cron local por enquanto, migra pra job agendado no Oracle depois) que:
   - Copia SQLite files (rastafinancas, artists-booking) via `sqlite3 .backup` (não `cp` direto — evita corrupção de arquivo em uso)
   - `pg_dump` do vetcare Postgres
   - `docker run --rm -v <volume>:/data -v $(pwd):/backup alpine tar czf /backup/<volume>-<date>.tar.gz /data` para os volumes Docker (influx, glitchtip, grafana, vault)
2. Destino do backup: fora da máquina local (não adianta backup no mesmo disco). Proposta: bucket S3-compatível — Oracle Object Storage (free tier já cobre, é S3-compatible) ou Cloudflare R2 (free tier generoso). Decisão pendente (ver abaixo).
3. Retenção definida (ex: diário 7 dias, semanal 4 semanas) — não guardar infinito.
4. Restore testado pelo menos uma vez (backup que nunca foi restaurado não é backup, é esperança).
5. Vault especificamente: unseal keys/root token backupeados separadamente do volume (idealmente nunca em texto claro no mesmo lugar que o resto — considerar guardar em gerenciador de senha pessoal, não só no backup automatizado).

## Decisões Necessárias

- [ ] D1: destino do backup — Oracle Object Storage (mesma cloud do `oci-free`, zero custo extra) vs Cloudflare R2 (já usa Cloudflare pra tunnel/DNS)?
- [ ] D2: frequência — diário é suficiente pro seu caso de uso (projetos pessoais, não produção 24/7 com SLA)?
- [ ] D3: esse script roda local (WSL2, via cron) até o Oracle existir, ou espera o Oracle pra já nascer lá?

## Tasks (após decisões)

| # | Task |
|---|---|
| 1 | Script `infra-platform/scripts/backup.sh` — SQLite + Postgres + volumes Docker |
| 2 | Upload pro destino escolhido (D1) |
| 3 | Cron/agendamento (local por enquanto) |
| 4 | Restore testado e documentado (`docs/how-to/restore-from-backup.md`) |
| 5 | Vault: procedimento separado de guarda de unseal keys |
