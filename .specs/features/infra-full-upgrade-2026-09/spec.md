# SPEC: Atualização completa da infra (platform stack + sidecars por produto + IaC + runtime)

## Status: APPROVED — 2026-09-15 (D1–D6 respondidas, ver DECISIONS.md D-2026-09-15-1; D2/D3 com
escopo ampliado por decisão explícita do usuário: tudo na última LTS mesmo com migração)
## Created: 2026-09-12
## Owner: rodrigo

## Contexto

Levantamento real feito em sessão anterior (não assumido — lido `platform/docker-compose.yml`,
composes dos 4 produtos, Dockerfiles, `terraform/*.tf`, versão instalada do Terraform CLI, e
comparado com a última versão estável/LTS de cada serviço via fonte externa).

Nenhum dos 5 produtos está em produção ainda, e o usuário já passou pela rodada de feedback —
decisão explícita: **atualizar tudo de uma vez, corrigindo breaking changes onde existirem, downtime
aceito**. Isso muda o cálculo de risco normal (normalmente HIGH blast radius pararia aqui para
aprovação por item) — a aprovação aqui é para o pacote completo, registrada nesta spec.

## Inventário + gap (fonte: sessão de levantamento, 2026-09-12)

| # | Serviço | Onde | Atual | Alvo | Tipo de mudança |
|---|---|---|---|---|---|
| 1 | Terraform CLI | máquina local (`~/.local/bin`) | 1.9.8 | 1.16.2 | minor, sem breaking conhecido |
| 2 | terraform-provider-oci | `terraform/{environments/oci-free,modules/oci-compute}/main.tf` | `~> 6.0` | `~> 9.0` | 3 majors — checar diffs de resource/attribute antes de `plan` |
| 3 | cloudflared | `tunnel/docker-compose.yml` | 2026.8.2 | 2026.9.1 | trivial |
| 4 | Caddy | `ingress/caddy/docker-compose.yml` (inativo) | `2-alpine` (flutuante) | pin `2.11.4` | hygiene, sem breaking (ainda não está em uso) |
| 5 | OTEL Collector Contrib | `platform/docker-compose.yml` | 0.103.0 | 0.160.0 | 57 minors — checar `otel-collector-config.yaml` contra changelog (processors/receivers renomeados) |
| 6 | Prometheus | `platform/docker-compose.yml` | v2.55.1 | v3.14.0 | **major** — Content-Type de scrape passa a ser estrito, `.` em regex passa a casar `\n`, `scrape_classic_histograms`→`always_scrape_classic_histograms`, `enable_http2` remote_write default muda pra `false` |
| 7 | Grafana | `platform/docker-compose.yml` | 10.4.0 | 13.2.1 | 3 majors — checar provisioning (`dashboards/*.json`, datasources) e plugins compat |
| 8 | Loki | `platform/docker-compose.yml` | 2.9.10 | 3.7.7 | **major** — exige schema v13 + TSDB (config atual provavelmente `boltdb-shipper`, precisa migração de schema, não só bump de imagem) |
| 9 | Promtail (4 produtos: rastafinancas, microgrow, vetcare, artists-booking) | `*/promtail/config.yml` + composes | 2.9.0 | **EOL desde 03/2026** | não é bump — substituição arquitetural por Grafana Alloy |
| 10 | GlitchTip | `platform/docker-compose.yml` | v4.2.4 | v6.x | **não suporta upgrade direto 4→6** — precisa passar por 5.x primeiro; muda porta interna pra 8000, exige Redis/Valkey ≥7 (já temos 7, ok), evento legado precisa `import_legacy_events`/`GLITCHTIP_RETAIN_LEGACY_DATA` se quiser manter histórico |
| 11 | Postgres (glitchtip-db) | `platform/docker-compose.yml` | `16-alpine` | pin `18` | 2 majors — precisa dump/restore (não é upgrade in-place entre majors do Postgres) |
| 12 | Postgres (vetcare app + evolution-api) | `vetcare/docker-compose.dev.yml`, `vetcare/infra/evolution/docker-compose.yml` | `16-alpine` | pin `18` | idem — dump/restore, 2 bancos |
| 13 | Redis (glitchtip-redis) | `platform/docker-compose.yml` | `7-alpine` | pin `8` | licença voltou pra AGPLv3 (era preocupação, não é mais) — sem breaking técnico relevante pra uso single-node |
| 14 | Telegraf (rastafinancas, microgrow) | composes de observability | 1.30 | 1.40.0 | 10 minors — checar plugins `inputs.http`/`outputs.influxdb_v2` contra changelog |
| 15 | eclipse-mosquitto (microgrow) | `microgrow/infra/docker-compose.yml` | `2` (flutuante) | pin `2.1.2` | patch, sem breaking |
| 16 | InfluxDB | `platform/docker-compose.yml` | 2.7 | v3 é o produto atual (reescrita em Rust) | **ver D3 — decisão de escopo, não é bump simples** |
| 17 | Node.js (Dockerfiles artists-booking, rastafinancas, vetcare) | `apps/*/Dockerfile*` | `22-alpine` | `24-alpine` (LTS ativa) | breaking changes de runtime possíveis, requer rodar suíte de teste de cada app — ver D4 |
| 18 | mailhog (artists-booking, dev only) | `docker-compose.dev.yml` | `latest` (sem pin, projeto sem manutenção ativa) | ver D5 | não tem LTS aplicável — decisão é trocar de ferramenta ou só pinar o hash atual |
| 19 | atendai/evolution-api (vetcare) | `vetcare/infra/evolution/docker-compose.yml` | `latest` (sem pin) | pin explícito | hygiene — precisa achar a tag/versão real antes de pinar |

`developerFolio` (node:10) fica **fora de escopo** — já registrado como item separado, escalado em
sessão anterior (fork público com CI em `master`), não faz parte deste pacote.

## Decisões necessárias antes de executar (D1–D6)

- **D1 — GlitchTip**: aceitar o hop obrigatório 4.2.4 → 5.x → 6.x (duas migrações de banco em
  sequência, não uma), ou ficar em 5.x por agora e reavaliar 6.x depois? Recomendação: fazer os
  dois hops agora, já que downtime está aceito e não há dado de produção — evita repetir o
  trabalho de migração de banco depois.
- **D2 — Loki**: migrar schema pra v13/TSDB (exigido pelo Loki 3.x) descartando os logs antigos
  armazenados no formato antigo, ou rodar o passo de migração de índice documentado pela Grafana
  antes do bump? Recomendação: **descartar** — são logs de dev/homolog, sem valor de retenção, e
  a migração de índice é o passo mais arriscado desta lista inteira pra um ganho baixo.
- **D3 — InfluxDB v2 → v3**: são produtos diferentes (motor de storage, linguagem de query — Flux
  sai de linha, vira SQL/InfluxQL). Dashboards do Grafana, `telegraf.conf` (`outputs.influxdb_v2`)
  e o simulador do microgrow escrevem assumindo v2. Três opções:
  (a) migrar pra v3 agora (reescreve outputs/queries/dashboards, maior escopo desta spec inteira),
  (b) ficar pinado no último patch da série v2 (ainda recebe patch de segurança, mas é motor em
  fim de vida do produto), (c) adiar InfluxDB pra uma spec própria depois desta.
  Recomendação: **(c)** — separar numa spec própria por ser o item de maior escopo/risco e não
  bloquear o resto do pacote nele.
- **D4 — Node 22→24 nas apps**: bump de major runtime em 3 repos de produto (artists-booking,
  rastafinancas, vetcare) toca `Dockerfile`, possivelmente `package.json` engines, e exige rodar a
  suíte de testes de cada app (fora do escopo de `harness-infra`, que só troca a imagem base).
  Confirma: delego a execução do bump de Dockerfile aqui (é infra), mas a validação de
  compatibilidade de código (rodar `npm test`/`tsc` pós-bump) fica marcada como gate obrigatório
  antes de fechar cada repo — se algo quebrar, abro spec própria em `harness-dev` pro fix, não
  tento consertar código de produto por esta spec.
- **D5 — mailhog / evolution-api (`:latest` sem pin)**: mailhog é ferramenta de dev sem LTS
  (recomendo só fixar a tag pelo digest atual, sem trocar de ferramenta). evolution-api: preciso
  investigar a tag/release real antes de pinar (repo migrou de `EvolutionAPI` pra
  `evolution-foundation` — checar se `atendai/evolution-api` no Docker Hub ainda é publicado a
  partir do fork certo). Confirma que investigo e pino, sem trocar de projeto?
- **D6 — Ordem/janela**: executo em lotes sequenciais (cada lote fecha gate antes do próximo) na
  ordem abaixo, tudo numa sessão só já que downtime está aceito, ou prefere lotes em dias
  separados?

## Plano de execução (após D1–D6), em lotes — cada lote fecha gate antes do próximo

### Lote 0 — Pré-voo (sem risco, roda sempre)
- Rodar `scripts/backup.sh` (já existe, validado) antes de tocar qualquer serviço com dado
  (Postgres x2, InfluxDB, GlitchTip, Vault).
- Tag git em cada repo tocado (`pre-infra-upgrade-2026-09`) pra rollback rápido de compose/config.

### Lote 1 — Tooling (sem dado, sem downtime de serviço rodando)
- Terraform CLI 1.9.8 → 1.16.2.
- `terraform-provider-oci` `~>6.0` → `~>9.0`, `terraform init -upgrade` + `terraform validate` +
  `terraform plan` (sem `apply` — ambiente `oci-free` ainda não provisionado, plan é o gate real).

### Lote 2 — Promtail → Grafana Alloy (os 4 produtos)
- Maior mudança estrutural da spec. Um produto por vez: converter `promtail/config.yml` via
  `alloy convert --source-format=promtail`, validar sintaxe, subir, confirmar log novo chegando no
  Loki (mesmo padrão de gate usado em `observability-promtail-docker`, já comprovado).
- Ordem sugerida: microgrow (já tem `docker_sd_configs` funcional, menor risco de regressão) →
  rastafinancas → vetcare → artists-booking.

### Lote 3 — Platform stack, serviços sem migração de schema
- cloudflared, Caddy (pin), OTEL Collector Contrib (checar config contra changelog antes do bump).

### Lote 4 — Prometheus v2→v3
- Checar `prometheus.yml` contra os 4 breaking changes listados no inventário (regex `.`, content-type,
  `scrape_classic_histograms`, `enable_http2`) antes do bump. Gate: `promtool check config` +
  4/4 produtos com targets `up` depois do restart.

### Lote 5 — Loki v2→v3 (após D2)
- Aplicar schema v13/TSDB conforme D2. Gate: `docker compose config` + ingest de log novo real
  (mesmo padrão de query no Loki API já usado antes).

### Lote 6 — Grafana 10→13
- Backup de dashboards (export JSON, já ficam versionados em `platform/dashboards/`) antes do
  bump. Gate: todos os dashboards provisionados carregando sem erro via API (`/api/search` +
  `/api/dashboards/uid/...`), datasources `up`.

### Lote 7 — Vault 1.17→2.x
- Ler change tracker da versão intermediária relevante antes do bump (HCL com atributo duplicado
  passa a falhar sempre — checar `vault-policies/*.hcl`). Gate: unseal bem-sucedido, `vault status`,
  `vault-push-env.sh` reconfirmando os 4 AppRoles.

### Lote 8 — GlitchTip 4→5→6 (dois hops, D1) + Postgres/Redis do GlitchTip
- Dump do `platform-glitchtip-db` antes de cada hop. Redis 7→8 primeiro (pré-requisito do
  GlitchTip 6, sem breaking esperado). Postgres 16→18 via dump/restore (não in-place). Depois
  GlitchTip 4.2.4→5.x (gate: web+worker up, login funciona) →6.x (gate: mesmo + porta 8000
  confirmada nos health checks internos, evento legado migrado se decidido manter).

### Lote 9 — Sidecars por produto
- Telegraf 1.30→1.40 (rastafinancas, microgrow) — checar plugins usados contra changelog.
- eclipse-mosquitto pin `2.1.2` (microgrow).
- Postgres 16→18 (vetcare app + evolution-api) — dump/restore, 2 bancos.

### Lote 10 — Runtime Node 22→24 (D4)
- Por repo (artists-booking, rastafinancas, vetcare): bump `Dockerfile`(s), `docker build`, rodar
  suíte de testes do repo. Se romper teste, para o lote naquele repo, registra achado, não
  conserta código aqui — abre acionamento pro `harness-dev` daquele repo.

### Lote 11 — Hygiene final (D5)
- Pin exato de tags flutuantes restantes (`postgres`, `redis`, `caddy`, `mosquitto` — já cobertos
  acima — e investigação+pin de `mailhog`/`evolution-api`).

### Fora desta spec (D3)
- InfluxDB v2→v3 — spec própria depois, por escopo/risco.

## Done Criteria
- Todos os itens do inventário (exceto InfluxDB, D3, e developerFolio, fora de escopo) na versão
  alvo, confirmados via `docker inspect`/`--version` real, não só o que está escrito no compose.
- `docker compose config` PASS em `infra-platform/platform`, `tunnel`, e nos 4 composes de produto.
- Gates externos por lote (listados acima) todos PASS, registrados em `.specs/audit/execution.md`
  a cada lote fechado (não só no final).
- Rollback testado em pelo menos 1 lote com dado (GlitchTip ou Postgres) antes de considerar a
  spec inteira DONE — prova de que o backup do Lote 0 realmente restaura.
- Node 22→24: 3/3 repos com bump de Dockerfile + suíte de teste rodada (PASS ou achado registrado
  e encaminhado, não escondido).
- STATE.md e DECISIONS.md atualizados a cada lote fechado, não só ao final.
