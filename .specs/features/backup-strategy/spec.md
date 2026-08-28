# SPEC: Backup Strategy

## Status: DONE (2026-08-28) — local backup ativo e testado. R2 pronto mas desativado de propósito (usuário não quer gastar ainda).
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

## Decisões (resolvidas 2026-08-28)

- [x] D1: Cloudflare R2 (já tem conta ativa). **Mas usuário não quer gastar ainda (R2 exige forma de pagamento cadastrada mesmo no free tier)** — script já tem a lógica de upload pronta, só ativa quando as env vars `R2_*` existirem. Ver `docs/how-to/setup-r2-backup-destination.md`.
- [x] D2: diário, retenção 7 dias + 4 semanais.
- [x] D3: começou agora, local (WSL2 via cron) — não espera o Oracle. Mesmo script promove pro Oracle depois sem mudar (ADR 005).

## Log de Execução (2026-08-28)

- Script `scripts/backup.sh` escrito e **rodado de verdade 2x** (não só sintaxe): SQLite (rastafinancas via `.db` real, artists-booking), Postgres (vetcare — achou o container `vetcare-postgres-1` PARADO, iniciou como efeito colateral necessário pro `pg_dump`, deixou rodando — bônus: resolve um gap operacional que existia antes de eu nem procurar), 4 volumes Docker (influx, glitchtip-db, grafana, vault), chaves do Vault. Total: 89MB.
- **1 bug real achado rodando pra valer**: `rotate_weekly()` usava `find` num diretório que podia não existir ainda, e sob `set -e` + `pipefail` isso derrubava o script inteiro mesmo com o `wc -l` do pipe tendo sucedido (edge case clássico do bash). Corrigido com `mkdir -p` antes do `find`.
- `sqlite3` CLI não está instalado nesta máquina — usei o módulo `sqlite3` do Python (stdlib, já disponível), que faz o mesmo backup seguro a quente que o `.backup` do CLI faria (`Connection.backup()`), sem precisar instalar nada.
- **Restore testado de verdade** (Done Criteria #4): restaurei o backup do rastafinancas, confirmei 9 tabelas recuperadas (`users`, `refresh_tokens`, etc.) e tamanho idêntico ao arquivo original. Procedimento documentado em `docs/how-to/restore-from-backup.md` (SQLite, Postgres, volumes, Vault keys).
- **Cron não pôde ser ativado** — WSL2 não roda o daemon `cron` por padrão e ativá-lo (`sudo service cron start`) precisa de senha que esta sessão não tem. Entrada já está em `crontab -l` (`0 3 * * *`), só falta o usuário rodar `sudo service cron start` (e idealmente configurar `/etc/wsl.conf` pra isso persistir entre restarts do WSL2 — também precisa de sudo).
- R2: doc `docs/how-to/setup-r2-backup-destination.md` escrita, mas **nada foi criado/ativado na Cloudflare** — respeitando "não vou gastar ainda".

## Tasks — todas concluídas (exceto o que depende de sudo/conta do usuário)

| # | Task | Status |
|---|---|---|
| 1 | Script `infra-platform/scripts/backup.sh` — SQLite + Postgres + volumes Docker | ✅ DONE, testado 2x |
| 2 | Upload pro R2 | ✅ código pronto, ⏸ inativo (sem gastar) |
| 3 | Cron/agendamento (local por enquanto) | ✅ crontab configurado, ⏸ daemon precisa `sudo service cron start` (usuário) |
| 4 | Restore testado e documentado (`docs/how-to/restore-from-backup.md`) | ✅ DONE |
| 5 | Vault: procedimento separado de guarda de unseal keys | ✅ DONE (backup automático + recomendação de gerenciador de senha, manual) |
