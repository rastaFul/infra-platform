# Metrics — infra-full-upgrade-2026-09

**Date:** 2026-09-15
**Scope:** `.specs/features/infra-full-upgrade-2026-09/spec.md` — atualização completa da infra
(19 itens de inventário + D3 InfluxDB v2->v3 adicionado por decisão explícita do usuário)

## Duração e paralelismo
- Sessão única, downtime aceito (D6), começo ~15:43, fim ~20:00 (horário local, `-03:00`)
- 9 sub-agentes `task-executor` delegados em paralelo em 3 ondas:
  - Onda 1 (4 agentes): Promtail -> Alloy, 1 por produto
  - Onda 2 (3 agentes): Node 22 -> 24, 1 por repo
  - Onda 3 (2 agentes): reescrita Flux -> SQL, 1 por produto (rastafinancas 5 dashboards, microgrow 4)

## Itens do inventário — status final
| # | Item | Status |
|---|------|--------|
| 1 | Terraform CLI 1.9.8 -> 1.16.2 | DONE |
| 2 | terraform-provider-oci ~>6.0 -> ~>9.0 | DONE |
| 3 | cloudflared 2026.8.2 -> 2026.9.1 | DONE |
| 4 | Caddy pin 2.11.4-alpine (inativo) | DONE |
| 5 | OTEL Collector Contrib 0.103.0 -> 0.160.0 | DONE |
| 6 | Prometheus v2.55.1 -> v3.14.0 | DONE |
| 7 | Grafana 10.4.0 -> 13.2.1 | DONE |
| 8 | Loki 2.9.10 -> 3.7.7 | DONE (schema já era v13/tsdb, sem migração de dado) |
| 9 | Promtail (4 produtos) -> Grafana Alloy v1.19.2 | DONE (4/4) |
| 10 | GlitchTip 4.2.4 -> 5 -> 6.0.3 | DONE |
| 11 | Postgres (glitchtip-db) 16 -> 18 | DONE |
| 12 | Postgres (vetcare + evolution-api) 16 -> 18 | DONE |
| 13 | Redis (glitchtip) 7 -> 8 | DONE |
| 14 | Telegraf 1.30 -> 1.40.0 (2 produtos) | DONE |
| 15 | eclipse-mosquitto pin 2.1.2-alpine | DONE |
| 16 | InfluxDB v2 -> v3 Core | DONE (fora do escopo original, D3) |
| 17 | Node 22 -> 24 (3 repos) | DONE (bump), débito de produto pré-existente registrado, não corrigido |
| 18 | mailhog pin por digest | DONE |
| 19 | evolution-api `atendai/*` -> `evoapicloud/*` v2.3.7 | DONE |

19/19 + D3 = 20/20 concluídos.

## Bugs reais encontrados e corrigidos nesta sessão (não hipotéticos, todos verificados via gate externo)
1. Migration "fake applied" do GlitchTip desde 2026-06 (`performance.0015_transactiongroup_is_deleted`
   marcada aplicada sem a coluna existir) — nunca exercitada até o worker v5 rodar.
2. Postgres 18+ recusa volume montado direto em `.../data` num volume novo (repetido 3x: glitchtip-db,
   vetcare postgres, evolution-db) — mount no diretório pai resolve.
3. `otlphttp` (alias deprecated) vs `otlp_http` (nome canônico) no exporter do OTEL Collector.
4. Self-metrics do OTEL Collector (porta 8888) parou de subir silenciosamente (>=0.123.0 ignora
   `telemetry.metrics.address` antigo) — precisa da sintaxe `telemetry.metrics.readers`.
5. HEALTHCHECK do Loki quebrado pela remoção do BusyBox (`/bin/sh` inexistente) — travaria
   `depends_on: condition: service_healthy` do Grafana pra sempre.
6. Vault 2.x remove `cap_ipc_lock` da imagem — `disable_mlock=false` teria impedido o boot.
7. `eclipse-mosquitto:2.1.2` não existe no Docker Hub — tag real é `2.1.2-alpine`.
8. `atendai/evolution-api` não existe mais no Docker Hub — projeto migrou pra
   `evoapicloud/evolution-api`.
9. Volume novo do InfluxDB 3 nasce root-owned, container roda como uid 1500 não-root — permission
   denied no boot.
10. Token do datasource InfluxDB 3 do Grafana não atualizado em `platform/.env` (só nos `.env` dos
    produtos) — datasource ficou `Unauthenticated` até o `printenv` real revelar o token velho.
11. `environment.json` (microgrow) referenciava measurement `microgrow_raw`, que nunca existiu em
    nenhum `telegraf.conf` — bug pré-existente desde antes desta sessão, nunca teria funcionado nem
    no InfluxDB 2.7 antigo.
12. 3 mismatches reais de nome de medição/campo nos dashboards rastafinancas
    (`http_response_result_code`, `mem_used_percent`, `disk_used_percent`).
13. `/health` do InfluxDB 3 Core exige autenticação — sem endpoint anônimo, HEALTHCHECK sem header
    deixou o container `unhealthy` por ~30min apesar de 100% funcional (achado na varredura final).

## Gates finais (2026-09-15T20:00)
- docker compose config: 8/8 PASS
- terraform validate + fmt: PASS
- 6/6 domínios públicos sem 502
- 29 containers do ecossistema: nenhum crash loop, nenhum unhealthy remanescente
- infra-quality-gates (run + final): overall PASS (ferramentas ausentes = SKIPPED, nunca PASS falso)
- policy-gates: SKIPPED (conftest ausente)
- security-gates (run): FAIL — gitleaks achou 5 segredos, todos em `.env` gitignorados (não é leak
  de git, é scan de filesystem local vs. `--staged`)
- security-gates (final): FAIL — 1 HIGH trivy_config pré-existente, fora do escopo (Dockerfile do
  próprio harness sandbox)
- cost-gates: SKIPPED (infracost ausente)

## Rollback disponível
- Tags `pre-infra-upgrade-2026-09` em 5 repos (infra-platform, rastafinancas, microgrow, vetcare,
  artists-booking)
- Binário Terraform 1.9.8 preservado (`~/.local/bin/terraform.pre-upgrade-2026-09`)
- 4 volumes Postgres 16 antigos preservados intocados (glitchtip, vetcare, evolution-api)
- Container InfluxDB 2.7 (`platform-influxdb`) continua rodando, não desligado
- Configs Promtail antigas preservadas como histórico (não deletadas) nos 4 produtos
- 5 dumps SQL completos guardados no scratchpad da sessão (não versionados)

## Pendências / dúvidas para o usuário (ver DECISIONS.md D-2026-09-15-2)
Ver mensagem final da sessão — lista completa de itens que precisam decisão ou são follow-up.
