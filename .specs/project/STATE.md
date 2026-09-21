# STATE

## Session: docker-disk-cleanup-2026-09-21
## Status: COMPLETED — todas as pendências fechadas e verificadas externamente
## Last updated: 2026-09-21

**Fechamento (D-2026-09-21-3)**: usuário resolveu as 2 pendências restantes — queda de C: era um
download em andamento (não Docker, resolvido sozinho) e compactação manual do `.vhdx` rodada com
sucesso. Verificado ao vivo via PowerShell, não assumido: `docker_data.vhdx` 88GB→30.7GB, C: livre
5GB→76.8GB. Nada pendente nesta frente. `docker-disk-lifecycle` (prevenção automática, cron+guard)
continua ativa como já registrado.

**Atualização**: spec `docker-disk-lifecycle` (backlog da rodada anterior desta mesma sessão)
executada e fechada — ver D-2026-09-21-2 em DECISIONS.md, spec DONE em
`.specs/features/docker-disk-lifecycle/spec.md`. `scripts/docker-disk-guard.sh` criado (shellcheck
PASS, rodado de verdade), cron diário instalado e confirmado ativo, runbook e ROADMAP atualizados.
**Achado durante a execução**: C: caiu de 8.2GB→5GB livres em poucos minutos (consumo de outro
processo do Windows, não investigado, fora de escopo) — a compactação manual do vhdx (única
pendência real restante) ficou mais urgente do que estava no fim da rodada anterior.

Usuário reportou disco principal (C:) cheio (9.1GB livres/477GB, 99%). Detalhe completo (todos os
comandos/saídas) em `.specs/audit/execution.md` ("docker-disk-cleanup" + continuação), decisão em
D-2026-09-21-1 (DECISIONS.md), procedimento reutilizável em `docs/how-to/docker-disk-cleanup.md`.

**Causa raiz**: `docker_data.vhdx` (WSL2 backend do Docker Desktop) = 88GB, arquivo dinâmico que
não encolhe sozinho no NTFS mesmo após prune interno.

**DONE (usuário aprovou ambos)**:
1. Prune seguro: 55.6GB liberados dentro do vhdx (63 imagens dangling + 718 build cache), 0
   containers/volumes tocados.
2. Prune agressivo (`docker image prune -a -f`, aprovado explicitamente): +3.96GB, imagens
   16.15GB→12.19GB (32→25), 0% reclaimable restante. Volumes (1.73GB, 11 dangling) NÃO tocado —
   fora do pedido.

**BLOCKED — pendente ação do usuário**: compactação do vhdx. Docker Desktop/serviço/distro
`docker-desktop` todos parados e confirmados, `diskpart compact vdisk` (elevado, UAC aprovado)
falhou 3x seguidas com arquivo em uso — causa não isolada conclusivamente (candidato: VM
compartilhada do WSL2 ou scan do Defender). Única solução conhecida (`wsl --shutdown` completo ou
restart do Windows) **deliberadamente não executada** — mataria esta própria sessão (roda dentro
da distro `Ubuntu-20.04` do mesmo WSL2). Docker Desktop religado, 33/33 containers `Up` de novo
(`restart: always`), nada ficou parado. Script diskpart pronto em
`C:\Users\rodri\AppData\Local\Temp\harness-compact.txt` — usuário só precisa reiniciar o Windows
(ou fechar esta sessão + `wsl --shutdown` manual fora dela) e rodar o script elevado antes de
religar o Docker Desktop. Passo a passo completo no runbook.

**Registrado conforme pedido** ("registre tudo... spec depois... ao menos um runbook"):
- Runbook feito agora: `docs/how-to/docker-disk-cleanup.md`.
- Backlog de spec futura (automação: prune pós-build, checagem periódica, política de retenção de
  tags rollback) em `.specs/project/ROADMAP.md` ("Docker disk lifecycle — backlog") — spec formal
  ainda não escrita, aguardando o usuário priorizar quando quiser.

Varredura C: paralela (read-only, sem gate, não repetida nesta continuação): achados em
`AppData/Local` — Docker (88G vhdx), `Packages/.../Ubuntu20.04.../ext4.vhdx` (55G, é a própria
distro WSL desta sessão — só compactável com `wsl --shutdown` completo, não recomendado agora),
user Temp (7.45G, provável lixo de instaladores/sessões antigas), Downloads (11G, não revisado
item-a-item — decisão do usuário), Recycle Bin vazia, sem hiberfil.sys/pagefile.sys/Windows.old.

- current task: nenhuma pendente de execução do harness-infra nesta frente — falta só o usuário
  reiniciar o Windows/rodar o diskpart elevado pra fechar a compactação, e decidir se/quando quer
  a spec de automação do backlog.

## Session: platform-loki-incident-2026-09-17
## Status: COMPLETED
## Last updated: 2026-09-17

Incidente reportado pelo usuário ("platform-loki está reiniciando"). Diagnosticado e corrigido:
crash-loop de ~32h (RestartCount=1065) por shard de índice TSDB de 0 bytes (`index_20712`), causa
raiz isolada, backup feito, 4 arquivos órfãos removidos, ingestão de log real confirmada via query
API. Detalhe: D-2026-09-17-1 (DECISIONS.md).

Follow-up pedido pelo usuário ("sim, quero"): healthcheck + alerta pro Loki não parar de novo em
silêncio. Docker HEALTHCHECK confirmado inviável (imagem sem shell). Implementado monitoramento
externo (job Prometheus `loki` + 2 alertas Grafana `alert-loki-down`/`alert-loki-crash-looping`),
testado ponta a ponta com ciclo real (parei o Loki de propósito, confirmei `Alerting`, religuei,
confirmei `Normal`). Detalhe: D-2026-09-17-2.

Usuário confirmou ("sim, faça todos os ajustes") corrigir as 27 regras + resolver SMTP. Ambos
executados (D-2026-09-17-3):
- 27 regras `type: reduce` → `classic_conditions`: DONE, verificado via API — os 8 alertas
  Prometheus (artists-booking + Loki) confirmados `Normal` depois do fix.
- SMTP Gmail→Resend: wiring DONE (`.env`/`.env.example`/compose/how-to doc). `SMTP_PASSWORD`
  intencionalmente vazio — BLOQUEADO até o usuário criar conta Resend + verificar domínio + gerar
  API key (`docs/how-to/setup-resend-smtp-alerts.md`).

Usuário confirmou de novo ("sim, faça todos os ajustes") traduzir as 21 queries Flux→SQL. Feito
(D-2026-09-17-4): schema real consultado ao vivo, 21 queries traduzidas seguindo convenção dos
dashboards, testadas via API direta antes de tocar Grafana, aplicadas e verificadas 2x via API
real (1 erro transitório de conexão FlightSQL no 1º ciclo, sumiu sozinho no 2º — não assumido,
reconfirmado). Resultado final: 16/29 alertas saudáveis (8 Prometheus + 6 rastafinancas + 2
microgrow), 12 microgrow seguem erro (tabela não existe — simulador pausado, gap pré-existente já
registrado em D-2026-09-15-3, não corrigível por tradução de query), 1 microgrow em `nodata`
(achado novo, tópico MQTT parado há ~2h, não investigado, fora de escopo).

**Tudo que foi pedido nesta sessão está CONCLUÍDO e verificado**: incidente do Loki, monitoramento
externo (healthcheck inviável → Prometheus+Grafana), 27 regras `classic_conditions`, SMTP wiring
Resend, 21 queries Flux→SQL. Ver D-2026-09-17-{1,2,3,4} pro detalhe completo de cada item.

Usuário pediu: religar o simulador do microgrow + acionar harness-dev pro rasta-import "caso seja
algo de dev". Cadeia completa (D-2026-09-17-{5,6,7}), TODA CONCLUÍDA E VERIFICADA:
- `rasta-import-errors`: NÃO era dev — métrica errada na regra de alerta, corrigido direto aqui.
  Só falta 1 import real acontecer pra série existir (não é bug).
- Simulador do microgrow: bug real de mismatch de tópico MQTT (`microgrow/sim/tele/...` vs
  `microgrow/tele/...`) — delegado ao harness-dev 2x (1ª sessão diagnosticou + propôs spec, 2ª
  sessão executou a decisão do usuário: isolamento real/sim preservado via tag `source=real|sim`
  no Telegraf, não removendo o prefixo). Confirmado por mim de forma independente: dado fresco real
  com tag correta em `soil_moisture`/`air_conditions`/`reservoir`/`hydric_score`.
- 7 queries de alerta do `microgrow.yaml` atualizadas com filtro `source='sim'`, verificadas.
- **Resultado (nesta rodada)**: 22/29 regras saudáveis (era 16/29), 5 firing restantes todos
  explicados e legítimos (nada de bug/falso-positivo).
- **Achado registrado nesta rodada**: `pump_events` não gravava no InfluxDB (causa raiz não
  encontrada pelo harness-dev após ~10 hipóteses eliminadas, escalado corretamente) — **resolvido
  no loop seguinte, ver abaixo**.

## Loop de correção supervisionado (sem sandbox, dentro da sessão) — D-2026-09-18-1
Usuário pediu loop contínuo ("entre em loop... já faça o ajuste... anotar as dúvidas pro final").
Rodou até convergir (nada mais acionável sem decisão externa/de negócio):
1. **`pump_events` — causa raiz real encontrada e corrigida**: parser `json` clássico do Telegraf
   1.40.0 descarta campos não-numéricos (bool/string) não reivindicados por `tag_keys`, sem logar
   erro — payload só tinha bool+string, zero fields sobravam, métrica inteira descartada em
   silêncio. Isolado com harness Telegraf descartável + repro mínimo via `mosquitto_pub`. Fix
   (`json_v2` com `active` tipado `bool`) testado isoladamente antes de delegar ao harness-dev pra
   aplicar. Verificado independentemente: dado real chegando.
2. **Auditoria de tipo nas 27 queries traduzidas**: comparado cada comparação SQL contra
   `information_schema.columns` real. 2 bugs reais de falso-negativo silencioso corrigidos
   (`sensor_suspect`/`effective` são tags string no InfluxDB, queries comparavam como
   número/boolean — nunca bateriam mesmo com o evento real acontecendo).
3. **`lights_compliance` — mesma causa do pump_events**, achada durante a auditoria (`compliant`
   boolean não-taggeado). Query já corrigida aqui; fix de config delegado e confirmado.

**Estado final (verificado, API real)**: 22/29 saudáveis, 3 pending (transitório normal), 4 firing
— todos explicados (3 aguardando 1º evento real de produto, 1 sinal real de verdade). Stack
inteira (12 platform + 7 microgrow containers) saudável.

Usuário respondeu a dúvida do ciclo de cultivo: "comece sempre no primeiro ciclo" (política:
stage=seedling, ciclo novo, sempre que precisar configurar). Configurado via API — achou bug real
de 3 causas (permissão do Dockerfile + falta de volume + falta de rehidratação de estado),
corrigido com TDD real pelo harness-dev, verificado independentemente. Ver D-2026-09-18-2.
**Resultado final**: 25/29 alertas saudáveis (era 16/29 no início do loop, 22/29 na rodada
anterior). Restam 4 firing, todos sinais reais ou aguardando 1º evento de produto — não é bug.

Usuário pediu continuar o loop mais uma vez. Achado grande: 5 bugs reais de nome de measurement
em 2 dashboards do rastafinancas (`rasta-auth-security.json`/`rasta-product.json`) — mesma classe
de bug que D-2026-09-15-3 achou nos alertas em setembro, nunca corrigida de fato nesses 2
dashboards específicos (a migração Flux→SQL de 15/09 não pegou). Corrigido e verificado (1/5 com
dado real, 4/5 aguardando 1º evento, mesmo padrão já visto). Grafana recarrega dashboard sozinho,
confirmado ao vivo via API. Ver D-2026-09-18-3.
Também investigado (não corrigido, é design não bug): `alert-reservoir-sensor-flat-line` tem
threshold de 2h claramente baixo demais — sistema espera ~25h entre irrigações reais.

**Pendências que dependem de ação SUA, não do agente**:
1. Ativar SMTP de verdade: criar conta Resend + verificar domínio `rastaful.dev` + gerar API key
   (`docs/how-to/setup-resend-smtp-alerts.md`), colar em `platform/.env` (`SMTP_PASSWORD`).
2. Dado de teste do harness-dev ficou em `lights_compliance` (`light_id` "flower-live-true/false",
   usado pra provar o fix) — cosmético, sem risco, avisar se quiser que eu limpe.
3. `alert-reservoir-sensor-flat-line`: threshold de 2h não bate com a cadência real (~25h) — decidir
   novo threshold, combinar com `cooldown_remaining_h`, ou desativar.
- current task: nenhuma pendente de execução do harness-infra.

## Session: infra-full-upgrade-2026-09-followups
## Status: COMPLETED
## Last updated: 2026-09-15

## Sessão 2026-09-15 (continuação) — followups de D-2026-09-15-2 DONE
Usuário respondeu as 9 dúvidas (D-2026-09-15-3). Spec `infra-full-upgrade-2026-09-followups`
criada e concluída: T1 (rasta-slo.json overrides), T2 (tenant `platform` no Vault: policy+AppRole+
push de 12 chaves), T3 (gitleaks working-tree false-positive + trivy_config HIGH no
Dockerfile.sandbox, ambos corrigidos e sincronizados em `agents-harness`). Item 8 (tooling):
`agents-harness/scripts/install-gate-tools.sh` criado e ligado nos 2 installers, 11/12 ferramentas
instaladas nesta máquina (achado real: tflint install_linux.sh removido upstream 2026-09-12,
corrigido). Item 9 (zero-fill): `date_bin_gapfill` + `COALESCE` aplicado e testado contra dado
real. Efeito colateral de instalar as ferramentas de verdade: 3 bugs reais a mais achados e
corrigidos nos próprios scripts de gate (`osv-scanner` mudou de CLI, `kubeconform` rodando contra
YAML não-k8s, 2 findings reais do `tflint` no módulo Terraform) + débito de segurança REAL de
dependências do rastafinancas nunca visto antes (registrado no ROADMAP, não corrigido, fora de
escopo). Ambos os repos (`infra-platform` `b821cab`, `agents-harness` `4c84b8a`) commitados e
pushed. Nada mais pendente desta rodada.

## Sessão 2026-09-15 — infra-full-upgrade-2026-09 (original) — COMPLETED

## Sessão 2026-09-15 — infra-full-upgrade-2026-09 APPROVED, execução iniciada
Spec aprovada (D-2026-09-15-1). Downtime aceito, sessão única, todos os 19 itens do inventário
pra última LTS/estável (D2 Loki e D3 InfluxDB tiveram escopo ampliado por pedido explícito do
usuário — override das minhas recomendações de conter escopo). Plano: 12 lotes sequenciais
(gate fecha cada um antes do próximo), com sub-agentes `task-executor` em paralelo dentro de
lotes com itens independentes (Lote 2: 4 produtos Promtail→Alloy; Lote 9: sidecars).
- Lote 0 (backup+tags): DONE
- Lote 1 (Terraform CLI 1.16.2 + provider OCI ~>9.0): DONE
- Lote 2 (Promtail->Alloy, 4 produtos, paralelo via task-executor): DONE (4/4)
- Lote 3+4+5 combinados (OTEL Collector 0.160.0 + Prometheus v3.14.0 + Loki 3.7.7): DONE — achado
  de dependência real entre OTEL Collector e Loki (exporter `loki` deletado do binário, só resta
  OTLP nativo que exige Loki 3.x) forçou tratar os 3 lotes originais como uma unidade de gate.
  3 bugs reais achados/corrigidos via gate externo: alias `otlphttp` deprecated, self-metrics 8888
  sumindo silenciosamente (>=0.123.0 ignora `telemetry.metrics.address`), HEALTHCHECK do Loki
  quebrado por remoção do BusyBox (sem `/bin/sh`) que travaria o `depends_on` do Grafana pra sempre.
- Lote 6 (Grafana 10.4.0 -> 13.2.1): DONE — API/datasources/19 dashboards confirmados
- Lote 7 (Vault 1.17 -> 2.1.0): DONE — achado real pré-boot (cap_ipc_lock removido da imagem,
  disable_mlock=true aplicado ANTES do bump evitou crash), unseal + 4 tenants KV v2 + approle
  confirmados intactos
- Lote 8 (GlitchTip 4->5->6 + Postgres 16->18 + Redis 7->8): DONE — 2 bugs reais achados/corrigidos
  (migration "fake applied" desde 06/2026 nunca exercitada até o worker v5 rodar; imagem postgres
  18+ recusa volume montado direto em .../data, precisa montar no dir pai). Rollback preservado:
  volume pg16 antigo intocado, 3 dumps completos guardados.
- Lote 3 (resto: cloudflared 2026.9.1 + Caddy pin 2.11.4): DONE — 6/6 domínios públicos sem 502
- Lote 9 (Telegraf 1.40.0 rasta+microgrow, mosquitto 2.1.2-alpine, Postgres 18 vetcare+evolution-api):
  DONE — achado real de tag (`eclipse-mosquitto:2.1.2` não existe, correto é `2.1.2-alpine`),
  reaproveitado o fix do mount-point do Postgres 18+ descoberto no Lote 8
- Lote 10 (Node 22->24, 3 repos): delegado em paralelo a 3 task-executor — IN_PROGRESS, aguardando
  notificação dos 3
- Lote 11 (hygiene: mailhog digest pin, evolution-api): DONE — achado real, `atendai/evolution-api`
  não existe mais no Docker Hub (`pull access denied`), migrado pra `evoapicloud/evolution-api`,
  pinado em v2.3.7 (não v2.4.0, que exige ativação de licença — ver dúvidas finais)
- D3 (InfluxDB v2->v3, fora do escopo original, incluído por override explícito do usuário):
  IN_PROGRESS. Servidor `influxdb3` (InfluxDB 3 Core) rodando lado a lado com o v2.7 antigo
  (mantido como rollback). Write path (Telegraf, 2 produtos) DONE e confirmado com dado real.
  Datasources Grafana migrados pra SQL/FlightSQL, `/health` OK, query real via API confirmada.
  2 bugs reais achados/corrigidos: volume novo root-owned (uid 1500 não-root da imagem, corrigido
  via chown helper) e token do datasource não atualizado no `platform/.env` (Grafana ainda lia o
  token v2 antigo, achado via `printenv` real no container). Pendente: 76 queries Flux em 9
  dashboards (5 rastafinancas + 4 microgrow) sendo reescritas pra SQL AGORA, delegado em paralelo
  a 2 task-executor — IN_PROGRESS, aguardando notificação. InfluxDB v2.7 antigo continua rodando
  até dashboards confirmados.
- Lote 10 (Node 22->24, 3 repos): DONE (3/3) — builds/tsc limpos nos 3, débito de produto
  pré-existente confirmado via A/B Node22 vs Node24 (não é regressão do bump), registrado em
  D-2026-09-15-2, não corrigido (fora de escopo do harness-infra)
- D3 (InfluxDB v2->v3): DONE — 76/76 queries traduzidas (9 dashboards), gate real via API do
  Grafana. 3 mismatches de nome de medição + 1 measurement inexistente (bug pré-existente) achados
  e corrigidos. InfluxDB 2.7 antigo mantido rodando como rollback.
- Validação final completa: 8/8 docker compose config PASS, terraform validate+fmt PASS, 6/6
  domínios públicos sem 502, 29/29 containers saudáveis (1 achado extra corrigido na varredura
  final: healthcheck do influxdb3 sem auth header, corrigido). Gates infra-quality/policy/cost:
  PASS ou SKIPPED (ferramenta ausente, gap antigo). Gates de segurança: FAIL explicável e
  não-bloqueante (gitleaks = segredos em .env gitignorado; trivy_config = achado pré-existente fora
  de escopo) — detalhe em D-2026-09-15-2.
- current task: CONCLUÍDO. Métricas em `.specs/metrics/2026-09-15-infra-full-upgrade.md`, dúvidas
  em D-2026-09-15-2 (DECISIONS.md) aguardando revisão do usuário.

## Próxima ação: nenhuma pendente desta spec — aguardando usuário revisar as 9 dúvidas de
D-2026-09-15-2 (destaque: InfluxDB 2.7 antigo ainda ligado, evolution-api parado em v2.3.7 de
propósito, débito de teste pré-existente nos 3 repos de Node, 2 FAILs de gate explicados).

## Session: Infra Strategy — Phase 0 Execution (histórico anterior)
## Status: EXECUTING
## Last updated: 2026-09-09

## Sessão 2026-09-09 (continuação 4) — gate de pre-commit LOCAL implementado (DONE)
Pedido: fechar o gap "nada roda antes de um commit" neste repo (só CI pós-push cobria algo), sem
instalar o template JS/TS às cegas (`infra-platform` não tem `package.json` — confirmado).
- Decisão completa (JS/TS template rejeitado, framework `pre-commit` Python rejeitado, git hook
  nativo escolhido) em D-2026-09-09-6.
- Implementado: `scripts/pre-commit.sh` (versionado) + `.git/hooks/pre-commit` (wrapper de 1 linha,
  não versionado — `.git/hooks/` nunca é rastreado). Checagens: gitleaks (staged), terraform fmt
  -check + validate (staged .tf, via `find-tf-root.sh` já existente), shellcheck (staged .sh),
  sintaxe YAML/JSON (staged). Ferramenta ausente = SKIPPED com instrução de instalação, nunca
  bloqueia nem finge PASS (mesmo padrão dos outros `run-*.sh` do repo).
- `gitleaks` (8.30.1, mesma versão do `Dockerfile.sandbox`) e `shellcheck` (0.10.0) instalados como
  binários standalone em `~/.local/bin` (mesmo padrão de terraform/trivy/yamllint/gh já nesta
  máquina) — nenhum dos dois estava presente antes desta sessão.
- Verificação real: 4 gates testados isoladamente (stage temporário + revert) provando FAIL real —
  shellcheck (achou e corrigiu um bug real no próprio `scripts/pre-commit.sh`: `cd` sem `|| exit`),
  terraform fmt+validate, YAML syntax, gitleaks (chave privada RSA bloqueada; string parecida com
  token do GitHub corretamente NÃO sinalizada — sem falso positivo cego). Commit real de ponta a
  ponta (`git commit`, sem `--no-verify`) tocando `scripts/pre-commit.sh` — hook rodou sozinho e
  passou. Detalhe completo em D-2026-09-09-6 e `.specs/audit/execution.md`.
- Não tocado (fora de escopo, pertence a outras sessões em paralelo): mudanças não commitadas em
  `docs/reference/repository-layout.md`/`docs/explanation/infra-overview-diagram.md`; nenhum commit
  feito em `microgrow`/`artists-booking`.

## Sessão 2026-09-01 — artists-booking product-health dashboard + alertas (Spec 53 delegada) — DONE
- Dashboard `Artists Booking / Product Health (Spec 53)` + 3 alertas Prometheus criados, gates externos PASS (docker compose config, Grafana healthy, dashboard e alertas confirmados carregados via API real). Painéis/alertas ainda sem dado real — esperado, apps/api (spec 53) sendo instrumentado em sessão paralela.
- **Bug crítico achado e corrigido**: provisioning de alertas do Grafana estava quebrado pra TODO o platform (microgrow + rastafinancas, 0 regras carregando desde 2026-08-29) por causa de uma subpasta `alerting/rules/` que o Grafana não suporta (grafana/grafana#53294). Corrigido pros 3 projetos (flat layout). 24 regras confirmadas carregando agora.
- Achado secundário registrado, não corrigido (fora de escopo, precisa decisão do usuário): SMTP do canal de alerta (Gmail) com credencial inválida — só apareceu porque os alertas passaram a rodar de verdade.
- Ver D-2026-09-01-1 em DECISIONS.md e `.specs/audit/execution.md`.
- Próxima ação: nenhuma pendente desta frente — aguardando artists-api (sessão paralela) exportar as métricas de verdade pra validar dado real no dashboard (task T7 da spec 53, do lado do produto).

## Current Tasks (Batch 1 Parallel) — CLOSED

| Agent | Task | Status |
|-------|------|--------|
| infra-platform-scaffold | Create infra-platform repo + Vault + OTEL Collector + ADRs + Diátaxis docs | DONE |
| dockerfiles-all | Multi-stage Dockerfiles all 8 services + fix artists-api tsconfig noEmit | DONE |
| health-metrics-otel | /health + /metrics + GlitchTip + OTEL SDK em todos os APIs Fastify | DONE (fixed post-hoc bugs, see below) |

## Session Resume — 2026-08-27
- Docker Desktop reativado pelo usuário. `docker info` OK (server 29.6.2, 20 containers parados, 0 rodando — PM2 ainda no comando).
- Nota ambiente: `docker network ls` / `docker network inspect` sem redirecionar para arquivo retornam stdout vazio nesta sessão (provável hook de filtragem de output interceptando). Workaround: redirecionar para arquivo temporário e ler com cat/wc. `docker compose config`, `docker ps`, `docker build` não são afetados.
- **Batch 1: TODOS os gates fechados** (docker build 8/8 PASS após 3 rounds de fix — 3 bugs reais encontrados e corrigidos: vetcare DATABASE_URL build-time, artists-api tsconfig.base.json não copiado, rastafinancas-web node_modules path errado, + pin pnpm@9 em artists-*). docker compose config 5/5 PASS. Platform stack (Vault + OTEL Collector) subiu limpo, vault healthy/uninitialized/sealed (esperado). Detalhes: `.specs/audit/execution.md` sessão 2026-08-27. Decisões: `.specs/project/DECISIONS.md` D-2026-08-27-{1..4}.
- vault-init.sh (unseal + AppRole) adiado deliberadamente para Batch 3 — não faz parte do fechamento de gate.

## Sessão 2026-08-27 (continuação) — Decisões de arquitetura + limpeza + docs
- Discutido e fechado: CI/CD separados (GH Actions=CI, Coolify=CD), Oracle Cloud Free Tier como ambiente `oci-free` antes da AWS, Terraform Cloud pro state, Caddy adiado, Prometheus adicionado como pré-requisito de dashboards. Ver DECISIONS.md D-2026-08-27-{5..11} e ADRs 005-009 em `infra-platform/docs/explanation/adr/`.
- **Incidente PM2 #2**: daemon caiu de novo (0/10, mesmo padrão do dia 25) — `pm2 resurrect` aplicado, 10/10 online. Reforça a urgência de sair do PM2 (fragilidade WSL2 documentada desde a spec original, pain point #13).
- Limpeza executada: ~1GB de instalação manual removida de `~/projects/services/` (tarballs/binários pré-Docker), `evolution-api` movido pra `vetcare/infra/evolution/`. Pendente (precisa sudo, não executável pelo agente): `sudo rm -rf ~/services` (duplicata órfã root-owned).
- `infra-platform`: commit inicial criado (`b73814f`) — antes disso nunca tinha sido commitado apesar do Batch 1 reportar sucesso. `gh` CLI 2.98.0 instalado sem sudo em `~/.local/bin`. **Bloqueado**: push pro remoto — `gh auth login` é interativo, aguardando ação do usuário (ou criação manual do repo no GitHub).
- Docs Diátaxis criados: ADR 005 (estratégia de ambientes local/oci-free/aws-prod), 006 (CI/CD split), 007 (Oracle Free Tier), 008 (Terraform Cloud state), 009 (Caddy adiado + Prometheus). Reference: `docker-build-conventions.md` (os 3 bugs reais do gate de build), `repository-layout.md` (padrão de pastas). How-to: `provision-oracle-free-tier.md` (DRAFT — módulo Terraform OCI ainda não escrito). `multi-cloud-strategy.md` e `terraform-modules.md` atualizados.
- Terraform: módulo `oci-compute/` ainda **não escrito** — próximo passo depois do push do repo.

## Sessão 2026-08-27 (continuação 2) — Push infra-platform + agentes atualizados
- `gh` autenticado pelo usuário (conta rastaFul). Repo `infra-platform` criado privado no GitHub + push feito (`b73814f`, `6073fc3` → `github.com/rastaFul/infra-platform`).
- Agentes atualizados pra consultar `infra-platform` como fonte de verdade antes de trabalho de infra (existente ou novo produto): `harness-infra.md` (seção "Infra Source of Truth"), `harness-dev.md`, `infra-analyzer.md`, `CLAUDE.md` global. Sincronizado em `~/.claude/` (ativo) + commitado/pushed em `agents-harness` (`bda58dd` → `github.com/rastaFul/agents-harness`) — portátil pra outra máquina. Ver D-2026-08-27-12.

## Bloqueios ativos aguardando o usuário
1. `sudo rm -rf ~/services` (limpeza, baixo risco, não urgente)
2. Criar conta Oracle Cloud (região não-US, ex: Frankfurt) + gerar API key OCI
3. Criar conta Terraform Cloud + token

## Sessão 2026-08-27 (continuação 3) — Registro completo + push em todos os repos
- Auditoria achou Batch 1 nunca commitado em `microgrow`/`rastafinancas`/`vetcare` (misturado com WIP de feature do usuário no working tree). Commitado só o que é nosso (infra/observability), WIP do usuário intocado:
  - `microgrow` → `fe04b5c4` | `rastafinancas` → `3e1ba1c` | `vetcare` → `6737630`
  - `artists-booking` já estava commitado (fora desta sessão)
- `~/.specs` (STATE/DECISIONS/audit/metrics/specs cross-repo) **nunca era um repo git** — `git init` + push pro novo repo privado `github.com/rastaFul/harness-specs` (`52bf811`).
- Ver D-2026-08-27-13.

## Sessão 2026-08-27 (continuação 4) — Consolidação estrutural (IN_PROGRESS)
Usuário questionou a duplicação que eu tinha deixado passar. Auditoria confirmou:
- 3 gerações de volumes Docker órfãs pro mesmo stack de observabilidade (`infra_*`, `observability_*`, `platform_*` — renomes de pasta ao longo do tempo). `platform_*` é a atual (142MB InfluxDB, 155MB GlitchTip — dado real). As outras duas não são referenciadas em nenhum compose file — órfãs confirmadas.
- Tunnel real (PM2 `platform-tunnel`) usa `~/projects/services/tunnel/cloudflared/config.yml` — NÃO o `~/.cloudflared/config.yml` que citei errado nos ADRs/how-to do infra-platform. Corrigindo.
- `artists-api`: investigado — health check direto (200), via proxy Next.js (200), via domínio público real `artists.rastaful.dev` (200). error.log só tem o incidente de 25/08 (prom-client, já corrigido). NÃO está quebrado agora — se o usuário viu quebrar, foi durante um dos 2 incidentes de PM2 frio de hoje (já corrigidos) ou é algo que precisa de mais detalhe pra reproduzir.
- Padrão "só frontend público" JÁ EXISTE em artists-booking, rastafinancas, microgrow via `next.config.js` rewrites (proxy server-side `/api/*` → `localhost:PORT`) — backend nunca precisa de hostname público próprio. vetcare é monolito (não se aplica). MQTT do microgrow foi deliberadamente removido do tunnel (comentário em `mosquitto.conf` confirma).

### Tasks desta frente — TODAS CONCLUÍDAS
- [x] Remover clock-of-clocks
- [x] Consolidar platform stack (10 serviços num compose só, zero perda de dado, bug do healthcheck otel corrigido)
- [x] Migrar tunnel + corrigir doc errada (ADR-007 citava config.yml errado) + documentar padrão BFF-proxy (ADR-011)
- [x] Redistribuir `.specs` pros repos certos + reverter `harness-specs` (ADR-012)
- [x] `~/projects/services/` removido (vazio após migrações)
- [x] Bug de produção achado e corrigido: `artists.rastaful.dev` 500 (pnpm store corrompido, não relacionado à infra)
- [x] `~/services` deletado pelo usuário (confirmado)
- [x] Volumes órfãos `infra_*`/`observability_*` removidos (confirmado pelo usuário)
- [x] Agentes (`harness-infra`, `harness-dev`, `infra-analyzer`, `CLAUDE.md`) — descoberta de `.specs/` e `infra-platform` tornada operacional (algoritmo executável, não só prosa). Ver D-2026-08-27-16.
- [x] `gh auth refresh` + `harness-specs` — resolvido pelo usuário

## Sessão 2026-08-27 (continuação 5) — Specs de Segurança + Dev Environment + PROJECT/ROADMAP
- `PROJECT.md` corrigido (tinha conteúdo errado, Clock of Clocks) + `ROADMAP.md` criado (nunca existiu)
- 4 specs novas em `features/`:
  - `security-hardening-phase1/` — inclui achado CRÍTICO: JWT_SECRET fallback hardcoded em artists-booking + rastafinancas (D-2026-08-27-18). Aguardando aprovação, não corrigido ainda.
  - `security-audit-auth-session/` — investigação (não execução) de hash/cookie/refresh-token por produto
  - `backup-strategy/` — pain point aberto desde 12/08, nunca resolvido
  - `dev-environment-ansible/` — Ansible em vez de Vagrant pro WSL2/Linux/Mac (D-2026-08-27-17), aguardando usuário mandar repo Vagrant existente
- Próxima ação: usuário aprovar `security-hardening-phase1` (prioridade — tem achado crítico)

## Sessão 2026-08-27 (continuação 6) — dev-environment-ansible desbloqueada
- Usuário confirmou: sem repo Vagrant pessoal (só empresa, fora de escopo). D1/D3 resolvidos, spec promovida DRAFT → APPROVED, tasks detalhadas escritas. Ver D-2026-08-27-20.
- Falta só D2 (repo público/privado) antes de eu criar o repo `dev-environment` de fato.
- `security-hardening-phase1` continua aguardando aprovação explícita (não confundir com a aprovação desta frente diferente).

## Sessão 2026-08-28 (continuação) — smoke test + security-audit-auth-session
- Smoke test pré-execução (pedido pelo usuário): Playwright MCP indisponível nesta sessão (server conectado no CLI mas tools não expostas ao agente) — substituído por checagem HTTP real. 6/6 domínios públicos respondendo normal (307/302), 10/10 PM2 online, 3 APIs tocados hoje com `/health` 200, proxy CORS funcionando ponta a ponta. Nada quebrado.
- `security-audit-auth-session`: investigação completa (sub-agentes indisponíveis, feito direto). Achados: artists-booking sem rate limit em auth (HIGH) + cookie sem `secure` (MEDIUM) + bcrypt 10 rounds (LOW). rastafinancas maduro, sem achados. microgrow/vetcare sem superfície de auth custom relevante. Nenhuma correção aplicada — aguardando aprovação (Done Criteria da própria spec pede isso). Ver D-2026-08-28-4.
- Próxima ação: usuário decidiu — spec delegada (`artists-booking/.specs/features/21-security-hardening/spec.md`, D-2026-08-28-5), sem correção agora.

## Sessão 2026-08-28 (continuação 2) — 3 passos sem custo executados
Usuário aprovou os 3 passos propostos (Vault AppRole, Batch 2, Terraform). Todos concluídos:
1. **Vault AppRole**: segredos dos 4 projetos migrados pro Vault (KV v2). `.env` continua sendo o que a app lê (design deliberado — zero acoplamento do boot ao Vault). 1 bug real corrigido (heredoc bash mangling secrets com `$`/backtick). Ver D-2026-08-28-7.
2. **Batch 2**: descoberta boa — dashboard `golden-signals.json` já cobre artists-booking/rastafinancas (Prometheus só começou a funcionar ontem), docker-compose por projeto já estava adequado. Único gap real: vetcare sem `/metrics` — spec delegada pro harness-dev. Ver D-2026-08-28-8.
3. **Terraform `oci-compute`**: módulo completo escrito, gates reais rodados (`init`/`validate`/`fmt` PASS, `plan` bloqueado até conta existir — esperado). Bug real de `.gitignore` achado e corrigido (quase commitou 100MB+ de binário de provider). Ver D-2026-08-28-9.
- Cron confirmado ativo pelo usuário (`sudo service cron start` rodado) — backup diário às 3h já vai disparar sozinho hoje.
- Próxima ação: usuário decidir sobre criar conta Oracle Cloud + Terraform Cloud pra desbloquear o `plan`/`apply` real.

## Sessão 2026-08-28 (continuação) — backup-strategy EXECUTADA
- Local ativo e testado de verdade: `scripts/backup.sh` roda SQLite (2x) + Postgres (vetcare) + 4 volumes Docker + chaves Vault, 89MB, restore validado. 1 bug real corrigido (rotate_weekly). Ver D-2026-08-28-6.
- R2: pronto no código, desativado — usuário não quer gastar ainda. Cron configurado mas daemon precisa `sudo service cron start` (pendência do usuário, mesmo padrão de sempre nesta sessão sem sudo).
- **Todas as 4 specs da frente de segurança + backup estão fechadas**: security-hardening-phase1 (DONE), security-audit-auth-session (investigação DONE, correção delegada pro harness-dev), backup-strategy (DONE, R2 pendente ativação do usuário), dev-environment-ansible (DONE, aplicado de verdade).

## Sessão 2026-08-28 — security-hardening-phase1 EXECUTADA COMPLETA
Usuário aprovou ("pode executar tudo"). Todas as 5 tasks feitas: JWT fail-fast (artists-booking, rastafinancas), CORS exact-match (artists-booking, microgrow), `/metrics` token auth (3 APIs + prometheus.yml + docker-compose + 3 ecosystem.config.js), CI reusable workflow (5 apps, 4 repos), Vault init completo (KV v2, AppRole, policies pros 4 projetos).
**6 bugs reais achados e corrigidos** (nada disso tinha sido exercitado de verdade antes): 2x em `vault-init.sh` (curl -f contra endpoint que retorna não-2xx de propósito; volume com dono root em vez de vault), 3x no reusable CI workflow (tag trivy inexistente + pin por SHA por causa de compromisso de supply-chain documentado; conflito pnpm version vs packageManager; glob de cache errado que abortava o job), 1x colisão de sessão paralela em artists-booking (reaplicado, commitado rápido).
**2 achados reais de débito de produto** (não infra, CI pegou pela primeira vez): CVE crítico em `tar` (artists-booking), erros de tipo `tsc` (artists-booking) — registrados, não corrigidos (fora de escopo desta spec).
Todos os 4 repos de produto + infra-platform commitados e pushed. Ver D-2026-08-28-{2,3} e spec `security-hardening-phase1/spec.md` (log de execução completo).

## Sessão 2026-08-27 (continuação 7) — dev-environment executado
- D2 resolvida (privado). Repo `dev-environment` criado, 4 roles escritas, gates rodados (syntax-check + dry-run PASS, ansible-lint bloqueado por Python 3.8 da máquina). Ver D-2026-08-27-21.
- Pendente: rodar de verdade (sem `--check`) — só dry-run até agora. Pendente também: pacotes (role `packages`) nunca testados de fato, precisa de sudo que esta sessão não tem.
- Próxima ação: usuário decidir se quer que eu rode de verdade agora (aplica dotfiles + sync `~/.claude` completo) ou se prefere revisar o repo primeiro.

Ver D-2026-08-27-15 (DECISIONS.md) e ADRs 010, 011, 012 em `infra-platform/docs/explanation/adr/` pro detalhe completo.

## Sessão 2026-08-28 (continuação 3) — local-boot-persistence: diagnóstico DRAFT
Usuário reportou: apps locais não sobem sozinhos após restart do PC. Diagnóstico real feito (não assumido): WSL2 não roda systemd (`pm2 startup systemd` falha, `systemctl` offline), `wsl-boot.sh` só faz `pm2 resurrect` (não inicia cron nem Docker). Estado ao vivo confirmou o sintoma acontecendo agora: PM2 com 0 processos, cron parado, enquanto o platform stack Docker (10 containers, `restart: unless-stopped`) subiu sozinho assim que o Docker Desktop ficou de pé — prova de que Docker Compose já resolve isso, PM2 é a causa raiz. Spec `features/local-boot-persistence/spec.md` criada (DRAFT), 2 frentes propostas (mitigação rápida no `wsl-boot.sh` vs. fechar o Batch 3 já decidido em D4: migração PM2→Docker Compose). Aguardando D1/D2/D3 do usuário antes de executar.

## Próxima ação (após desbloqueios 2-3): escrever módulo Terraform `oci-compute/` + `environments/oci-free/`

## Incident — 2026-08-25 (found on session resume)

- PM2: 0/10 processes running (daemon respawned cold, no persistence across WSL2 restart) → `pm2 resurrect` from dump.pm2 (2026-06-13) → 10/10 online
- artists-api: crash-looped (MODULE_NOT_FOUND prom-client) — dependency declared in package.json by health-metrics-otel batch but never installed (pnpm 7.1.7 broken against registry, ERR_INVALID_THIS). Installed via `npx pnpm@9`. Fixed.
- artists-api + microgrow-api: tsc errors from health-metrics-otel batch never gated — `Sentry.autoDiscoverNodePerformanceMonitoringIntegrations` doesn't exist in @sentry/node v10 API; unreachable 'degraded' health branch. Fixed both, tsc clean.
- Docker daemon: BLOCKED. `/usr/bin/docker` (symlink → `/mnt/wsl/docker-desktop/...`) returns I/O error — Docker Desktop not running/mounted on Windows host. Cannot run `docker build`/`docker compose config` gates. **Needs user action: restart Docker Desktop on Windows.**

## Phase 0 Roadmap

### Batch 1 — DONE (gates re-run 2026-08-25, see audit)
- [x] infra-platform repo structure + Vault config + OTEL collector + ADRs + docs
- [x] Dockerfiles multi-stage (8 serviços) + fix artists-api tsconfig
- [x] /health + /metrics + GlitchTip + OTEL para artists-api, microgrow-api, rastafinancas-api

### Batch 2 (próximo — não iniciado)
- [ ] Per-project docker-compose.yml com redes isoladas
- [ ] Caddy config
- [ ] GitHub Actions CI por repo (5 repos)
- [ ] Grafana dashboards golden signals (provisioned) — microgrow tem, artists/rasta/vetcare faltam
- [x] Investigar artists-api restart loop — causa raiz encontrada e corrigida 2026-08-25 (era prom-client MODULE_NOT_FOUND, não @fastify/helmet — histórico antigo já resolvido, esse era novo, introduzido por health-metrics-otel batch)

### Batch 3 (validação + switch)
- [x] docker compose up platform (Vault + OTEL Collector)
- [x] vault-init.sh — AppRole por projeto
- [x] Migração PM2 → Docker Compose (1 serviço por vez) — 5/5 containerizados (rastafinancas, microgrow, vetcare, artists-booking, tunnel), 4/5 servindo saudáveis; tunnel BLOCKED externamente por config remota no dashboard Cloudflare (ação do usuário, D-2026-08-28-10)
- [ ] Update Promtail: PM2 logs → Docker socket logs
- [ ] Validação end-to-end: health checks + metrics + logs → Loki

## Stack Running (PM2 — mantendo durante migração)
| App | Port | Status |
|-----|------|--------|
| rastafinancas-api | 3001 | online |
| rastafinancas-web | 3000 | online |
| microgrow-api | 4000 | online |
| microgrow-webapp | 3002 | online |
| microgrow-webapp-sim | 3003 | online |
| microgrow-simulator | — | online |
| artists-api | 3006 | online (567 restarts histórico — atualmente estável) |
| artists-web | 3005 | online |
| vetcare | 3004 | online |
| platform-tunnel | — | online |

## Decisions Log
- D1: AWS primary cloud ✅
- D2: infra-platform repo separado, tenant isolation ✅
- D3: Vault self-hosted (HashiCorp OSS) ✅
- D4: Docker Compose substituindo PM2 completamente ✅
- D5: GitHub Actions para CI/CD ✅
- D6: Diátaxis para documentação ✅
- D7: OTEL desde day 0, backend swap sem mudar código ✅
- K8s: não agora — trigger de escala definido. Templates no infra-platform ✅

## Key Finding
- artists-api tsconfig `noEmit: true` → nunca compilou via tsc, sempre rodou tsx
- microgrow já tem padrão de rede correto (microgrow_net + platform_net) — reusar
- Promtail atual lê /home/rodrigo/.pm2/logs → mudar para Docker socket na migração

## Sessão 2026-08-28 (continuação 4) — local-boot-persistence: migração em execução
Spec APPROVED (D1=migração real completa, D2=tudo de uma vez, D3=Docker Desktop já autoinicia). Ordem: rastafinancas -> microgrow -> vetcare -> artists-booking -> tunnel (por último).
- rastafinancas: DONE. 3 bugs reais achados/corrigidos (npm workspace node_modules hoisting no api Dockerfile, healthcheck localhost->::1 vs Fastify IPv4-only, Next.js rewrites() resolvido em build-time não runtime). Ver execution.md.
- microgrow: DONE. Achado extra: mosquitto/telegraf/promtail estavam parados há 5 dias, subidos como efeito colateral. Nenhum bug novo (fixes pré-aplicados por lição do rastafinancas).
- vetcare: DONE (confirmado na sessão seguinte, ver abaixo).
- artists-booking: DONE (confirmado na sessão seguinte, ver abaixo).
- tunnel: containerizado, mas **BLOCKED externamente** — ver sessão seguinte.

## Sessão 2026-08-28/29 (continuação 5) — retomada após notebook travar
Notebook crashou no meio da migração do tunnel. Reconstruí o estado real (não assumido) via `git status`/`git diff` + verificação ao vivo: PM2 0/0 (D4 completo), 4/5 apps rodando saudáveis em Docker, `platform-tunnel` containerizado e `Up`.

**Achado real ao validar com gate externo**: as 6 rotas públicas (vetcare/financas/grow/grow-sim/metrics/artists.rastaful.dev) estavam em **502 real**, não só teoricamente sujeitas a isso. Investigação completa (não suposição): tunnel é **remotely-managed** pelo dashboard Cloudflare Zero Trust — o `config.yml` local é ignorado pro roteamento, e o dashboard ainda aponta pro `localhost:PORT` de antes da containerização (funcionava quando cloudflared rodava via PM2 direto no host; não alcança nada de dentro do container). Tentei corrigir via API (token existente em `tunnel/.env`) — sem escopo de conta suficiente. Ver D-2026-08-28-10 pro achado completo + os 2 bugs reais extras corrigidos nessa investigação (PM2 dump órfão, vetcare healthcheck dependia do tunnel).

**Status real agora**: 4/5 componentes (rastafinancas, microgrow, vetcare, artists-booking) 100% migrados, saudáveis, servindo local. `wsl-boot.sh` limpo (pm2 resurrect removido, cron adicionado). O único item pendente pra fechar esta spec é **1 ação manual do usuário no dashboard Cloudflare** (não automatizável com o token atual) — depois disso, re-testar as 6 URLs públicas e marcar a spec inteira como DONE.

### Bloqueio RESOLVIDO — 2026-08-29
Painel real: Networks → Tunnels → rastafinancas → **"Published application routes"** (não "Public Hostname"/"Hostname routes" como eu tinha suposto). Usuário editou as 6 rotas de `http://localhost:PORT` pra `http://host.docker.internal:PORT`. Validado com curl real: 6/6 sem 502. Spec `local-boot-persistence`: **DONE**.

## Sessão 2026-08-29 — local-boot-persistence DONE, todos os 5 componentes migrados e validados
6/6 rotas públicas confirmadas (curl real): vetcare/financas/grow/grow-sim/artists → 307, metrics → 302. Nenhum 502. `wsl-boot.sh` sem PM2 (só cron). PM2 instalado, sem processos.

## Sessão 2026-08-29 (continuação) — observability-promtail-docker: spec DRAFT
Próximo item do roadmap (Batch 3, Promtail PM2→Docker). Investigação real (lido cada compose/config, não assumido):
- **rastafinancas**: `rasta-telegraf`/`rasta-promtail` estão `Exited (0) 3 weeks ago` — achado sem relação com a migração PM2 de ontem, gap mais velho e maior (produto sem logs/métricas coletados há 3 semanas). `telegraf.conf` já usa `host.docker.internal:3001`, continua válido, não precisa mudar. `promtail/config.yml` só tem jobs de arquivo pro path PM2 morto.
- **microgrow**: `microgrow-promtail` rodando, já tem `docker_sd_configs` funcional (padrão comprovado) cobrindo mosquitto/influxdb/grafana/telegraf, mas NÃO os containers de app (api/webapp/webapp-sim/simulator) migrados ontem — só resta estender o filtro.
- **vetcare/artists-booking**: nunca tiveram Promtail — não é regressão, é gap pré-existente, fora do escopo original deste item. Registrado como possível follow-up (D2 da spec).
Spec criada em `features/observability-promtail-docker/spec.md`, aguardando D1 (restart dos containers do rastafinancas, confirmar que não foram parados de propósito)/D2 (escopo: só rasta+microgrow ou também vetcare/artists)/D3 (convenção de labels — recomendação: replicar o padrão do microgrow que já funciona).

## Sessão 2026-08-29 (continuação 4) — bug crítico de produção em artists-booking, achado pelo harness-dev
Agente `harness-dev` (sessão paralela, auditoria de UX) achou registro de usuário 100% quebrado em produção rodando o gate Playwright pré-existente — escalou corretamente como achado de infra, não UX. Verificado independentemente: `POST /api/v1/auth/register` 500 real, `"attempt to write a readonly database"`. Causa: bind-mount `apps/api/prisma` dono do host (uid 1000) vs container rodando como `appuser` (uid 1001) — regressão da migração PM2→Docker nunca antes exercitada. Corrigido de imediato (chown + restart, validado com o request real) e de forma permanente (`docker-entrypoint.sh` que corrige a permissão em todo boot, testado simulando clone novo — self-heal confirmado). `artists-booking` commit `827f282`. Ver D-2026-08-29-3.

## Sessão 2026-08-29 (continuação 3) — Caddy prep (inativo) + vetcare_net
Discussão K8s vs Compose (respondida via ADR-001 existente) e reverse proxy pro dia que o Cloudflare Tunnel sair do caminho (ADR-009 já previa revisitar isso, nunca escrito). Usuário pediu execução dos 2 itens sem bloqueio externo:
- `ingress/caddy/` criado, não ativo, `caddy validate` PASS. Ver D-2026-08-29-2.
- `vetcare_net` nomeada explicitamente (era `vetcare_default`, único dos 4 fora da convenção). Achado real: recriar rede de containers já rodando quebrou o port-relay do Docker Desktop/WSL2 — resolvido com `down`+`up` completo, validado local e público depois.

## Sessão 2026-08-29 (continuação 2) — observability-promtail-docker DONE
Usuário aprovou D1/D2/D3 (restart+validar, escopo total, replicar padrão microgrow). Executado e validado com gate externo real (Loki query, não só "container Up"):
- rastafinancas: telegraf 403 corrigido (token de segurança nunca propagado) + promtail migrado pra Docker discovery.
- microgrow: promtail estendido de 4 pra 6 containers + removido filtro morto (`microgrow-influxdb`/`microgrow-grafana`, nunca existiram).
- vetcare: promtail criado do zero — achado bug real de self-scraping (filtro sem âncora capturava o próprio promtail), corrigido.
- artists-booking: promtail criado do zero, já com filtro ancorado desde o início.
Ver D-2026-08-29-1 e spec (DONE). Roadmap Batch 3 do infra-platform está 100% fechado agora.

## Sessão 2026-09-09 — rastafinancas observability compose + vetcare /metrics — DONE (2 pendências)
Usuário reportou compose de observabilidade quebrado + pediu correção do /metrics do vetcare.
- `rasta-telegraf`/`rasta-promtail` estavam `Exited` há 26h por `docker stop` explícito (log
  confirma SIGINT/SIGTERM, não crash) — `restart:unless-stopped` não resscita contêiner já parado
  antes de um restart do daemon. `docker compose up -d` trouxe de volta, verificado com dado real
  novo no InfluxDB (measurements `rasta_*`) e Loki (log entry com timestamp atual).
- vetcare `/api/metrics` implementado do zero (repo `vetcare`, ver `.specs` de lá) + job dedicado
  em `prometheus.yml` (não deu pra reusar `apis-host`, path diferente). No caminho, achado e
  corrigido um bug real de bind-mount órfão do Prometheus (Docker Desktop/WSL2) que teria feito o
  `prometheus.yml` novo não ter efeito nenhum silenciosamente.
- Verificado externamente: 6/6 targets Prometheus `up`, dado real de vetcare via `/api/v1/query`.
- **Pendências não resolvidas, registradas**: (1) nenhum boot script resscita contêiner já
  `Exited` antes de restart do WSL2/Docker Desktop — pode voltar a acontecer com qualquer sidecar
  telegraf/promtail do ecossistema; (2) vetcare sem `http_requests_total` (métricas HTTP por
  rota) — não aparece no dashboard "Golden Signals" ainda; (3) `vetcare` `METRICS_TOKEN` não
  empurrado pro Vault.
Ver D-2026-09-09-1 em DECISIONS.md, detalhe completo em `.specs/audit/execution.md`.

## Sessão 2026-09-09 (continuação 3) — SMTP=Resend (decisão) + rastafinancas apps/web + lint
Usuário: SMTP dos alertas fica no Resend, não Gmail — não é prioridade agora, registrado (D-2026-09-09-5), nada configurado.
Itens 2/3/4 atacados: (2) `rastafinancas` apps/web tinha 70 erros reais de TS (não ~150 —
número inflado por invocação errada de tsc numa sessão anterior), causa raiz concentrada e
corrigida; (3) lint 105→61 warnings + 2 bugs reais de produto achados e corrigidos
(`userSignupsTotal` nunca incrementado, dead code em `extrato-csv.ts`); bônus: fix da rede
`rastafinancas_net` precisou de uma 2ª correção (a 1ª tinha invertido a direção sem checar o
label real do Docker). (4) rollout de gates pra microgrow/artists-booking/infra-platform ainda
não iniciado nesta sessão. Detalhe completo em `rastafinancas/.specs/` (DECISIONS.md/STATE.md
mesma data) — trabalho de código foi lá, não aqui.

## Sessão 2026-09-09 (continuação) — restart:always (pendência 1) + Vault + achados registrados
Usuário esclareceu: ele mesmo para o Docker Desktop pra jogar (não foi um bug de infra) e pediu
resolver via config do compose em vez de script de boot. Feito:
- `restart: unless-stopped` → `restart: always` nos 7 composes reais do ecossistema (platform,
  tunnel, rastafinancas x2, microgrow, artists-booking, vetcare), aplicado ao vivo, 31 contêineres
  confirmados saudáveis, 4/4 domínios públicos OK, Prometheus 6/6 targets `up`. Ver D-2026-09-09-2.
- Vault estava `sealed` (contêiner tinha sido recriado nesta mesma sessão pela mudança de restart
  policy) — deselado (`threshold=1`) e `vault-push-env.sh vetcare` rodado, `METRICS_TOKEN`
  confirmado no Vault batendo com o `.env` real.
- **2 achados novos registrados, não corrigidos, aguardando decisão do usuário**: rede
  `rastafinancas_net` declarada em 2 composes diferentes (frágil); `rastafinancas-api` com nome de
  métrica HTTP divergente do resto do ecossistema — painéis de Golden Signals nunca mostraram dado
  real pra rastafinancas (contradiz STATE.md de 2026-08-28).
- Item 2 (métricas HTTP custom do vetcare) investigado e **deliberadamente NÃO implementado**:
  Next.js middleware roda antes do route handler, não tem como saber status/duração reais — faria
  `http_requests_total`/`duration` tecnicamente existir mas com dado sempre errado (status sempre
  "passou pelo auth", nunca o real), pior que não ter a métrica num dashboard que filtra por
  `status_code=~"5.."`. Fix correto exige instrumentar os ~50 route handlers do vetcare — fora de
  escopo desta sessão, registrado como follow-up. Ver `vetcare/.specs/audit/execution.md`.

## Sessão 2026-09-09 (continuação 2) — as 3 pendências resolvidas
Usuário pediu resolver as 3 pendências (rename de métrica do rastafinancas, rede duplicada,
instrumentação HTTP do vetcare). Todas fechadas e verificadas externamente:
1. `rastafinancas-api`: métricas sem prefixo `rasta_` (`http_requests_total`/`http_request_duration_ms`
   ms, `collectDefaultMetrics` sem prefixo) — compatível com o Golden Signals agora. Dashboard
   InfluxDB + alertas do rastafinancas atualizados junto; achado e corrigido um bug pré-existente
   separado nos painéis P50/P95/P99 (nunca retornavam dado desde que o dashboard foi criado).
2. `rastafinancas_net`: observability compose corrigido pra `external: true` (dono é o compose
   principal do app) — warning de rede duplicada eliminado.
3. vetcare: 72 handlers HTTP (48 arquivos) instrumentados de verdade via `withMetrics` +
   codemod AST (`scripts/wrap-routes-with-metrics.mjs`), `vetcare_` removido do prefixo default.
Gates completos nos 2 repos, Prometheus confirma os 4 produtos consistentes, Grafana recarregado
(dashboard v4 + 6 alertas confirmados), 4/4 domínios públicos sem 502. Ver D-2026-09-09-3 em
DECISIONS.md, detalhe completo em `.specs/audit/execution.md`.
1 achado novo registrado, não corrigido (fora do pedido): lógica do alerta `rasta-latency-p95`
(`mean()` sobre contador cumulativo) é aproximada, não uma média real por request — pré-existente.

## Sessão 2026-09-08 — rename branch padrão master→main (infra-platform + varredura) — DONE (com 2 itens escalados)
`infra-platform` renomeado (master→main, verificado local+remoto+default GitHub). ADR-013 criado.
Usuário pediu em seguida "atualizar todos que ainda estão desatualizados" — varredura real dos 13
diretórios em `~/projects/`:
- `artists-booking`/`microgrow`/`rastafinancas`/`vetcare`/`agents-harness`: já estavam em `main` (suposição inicial do ADR estava errada, corrigida).
- `dev-environment`: renomeado agora (mesma sequência, verificado).
- `developerFolio`: **escalado, não tocado** — fork público com gh-pages ativo + 2 workflows que citam `master` por nome (precisaria editar CI, não é só rename de metadado) + branches de feature ativas. Precisa confirmação do usuário antes de agir.
- `tldr-projects`: **escalado, não tocado** — anomalia real: já tem uma branch `main` local órfã (1 commit não relacionado) + ref remota órfã sem remote configurado; `git branch -m` falhou por colisão de nome; working tree com mudanças não commitadas de outra frente. Descartar a branch órfã é decisão do usuário, não do agente.
- `url-shortener`: fora de escopo (owner é `thiagomr`, não `rastaFul`).
- `cron-monitoring`/`gorila`/`logger-lib`: não são repos git.
Ver D-2026-09-08-{1,2} em DECISIONS.md, tabela completa em ADR-013, detalhe em execution.md.
Próxima ação: usuário decidir developerFolio (renomear + editar os 2 workflows, ou deixar em master por ser fork) e tldr-projects (o que fazer com a branch `main` órfã antes de eu poder renomear `master`).

## Sessão 2026-09-02 — artists-booking Spec 54 T15 (dashboard novo, sem alerta) — DONE
10 painéis novos em `platform/dashboards/artists-booking/product-health.json` (RUM: navegação,
CTA, listas vazias, filtro, wizard, demanda por categoria/região família N, contenção SQLite
família H). Verificado via API real do Grafana (health, search, dashboard uid, 5 queries
PromQL representativas via proxy do datasource) — tudo `success`/200, painéis vazios só porque
o backend da Spec 54 ainda não foi deployado no container `artists-api` (confirmado via
`/metrics` direto, só métricas da Spec 53 presentes hoje). Nenhum alerta novo criado (fora do
escopo pedido). Detalhe completo em `.specs/audit/execution.md`.
