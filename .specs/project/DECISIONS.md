# DECISIONS

## D-2026-08-25-1: PM2 resurrect em vez de restart manual
Contexto: PM2 daemon subiu frio (0 processos) após restart do WSL2, dump.pm2 disponível (2026-06-13).
Decisão: usar `pm2 resurrect` (idempotente, reversível) em vez de recriar ecosystem manualmente.
Resultado: 10/10 processos restaurados.

## D-2026-08-25-2: pnpm@9 via npx como workaround para pnpm 7.1.7 quebrado
Contexto: `pnpm install` no artists-booking falha com `ERR_INVALID_THIS` (bug conhecido pnpm 7.x + Node 22/undici). `npm install` direto quebra o layout de node_modules do pnpm (symlinks, scripts de compile de deps hoisted).
Decisão: usar `npx -y pnpm@9 install --filter api...` — não altera pnpm global do projeto, resolve o install pontual.
Ação futura recomendada: atualizar `packageManager` do artists-booking para pnpm 9+ (não feito agora — fora do escopo do incidente, precisa spec própria por afetar lockfile do monorepo inteiro).

## D-2026-08-25-3: Remover `Sentry.autoDiscoverNodePerformanceMonitoringIntegrations()`
Contexto: API removida no @sentry/node v10 (usado por GlitchTip). Batch 1 (health-metrics-otel, 08-12) foi escrito contra API antiga e nunca gateado com tsc.
Decisão: remover a integração explícita — tracing automático já funciona via `tracesSampleRate` em v10. Aplicado em artists-api e microgrow-api.

## D-2026-08-25-4: Docker Desktop offline — não é responsabilidade do agente
Contexto: `/usr/bin/docker` → I/O error, mount WSL2↔Docker Desktop órfão. Não há como reiniciar Docker Desktop (processo Windows) a partir do shell WSL do agente.
Decisão: escalar para o usuário. Gates que dependem de Docker (`docker build`, `docker compose config` real) ficam BLOCKED até ação manual. Batch 1 fechado como DONE com essa ressalva registrada.

## D-2026-08-27-1: pin `pnpm@9` via corepack nos Dockerfiles de artists-booking
Contexto: `corepack prepare pnpm@latest` puxa pnpm 10+, que bloqueia scripts de instalação de deps nativas (esbuild, unrs-resolver) por padrão sob `--frozen-lockfile` (`ERR_PNPM_IGNORED_BUILDS`), quebrando `docker build`.
Decisão: pinar `pnpm@9` explicitamente nos Dockerfiles de artists-api e artists-web — consistente com D-2026-08-25-2, que já validou pnpm 9 como versão funcional para este repo. Ação futura recomendada (ainda não feita): atualizar `packageManager` no package.json raiz para pnpm 9+, escopo próprio (afeta lockfile do monorepo).

## D-2026-08-27-2: `DATABASE_URL` placeholder em build-time no Dockerfile do vetcare
Contexto: `next build` falha ao coletar page data de uma rota que importa o Prisma client eagerly (`src/lib/prisma.ts` lança erro se `DATABASE_URL` não está setado), mesmo sem nenhuma conexão real acontecer em build-time.
Decisão: `ENV DATABASE_URL="postgresql://build:build@localhost:5432/build_placeholder"` apenas no build stage do Dockerfile — nunca conecta de fato, só evita o throw eager. Runtime usa a URL real injetada via env/secret no start do container.

## D-2026-08-27-3: Fix de paths em Dockerfiles de monorepo (artists-api, rastafinancas-web)
Contexto: `docker build` (gate fechado nesta sessão) revelou dois bugs latentes nunca testados: artists-api não copiava `tsconfig.base.json` (extends quebrado, tsc caía em defaults sem esModuleInterop/target ES2022); rastafinancas-web copiava `/app/apps/web/node_modules` no runtime stage, mas `npm ci --workspaces` hospeda tudo em `/app/node_modules` (path nunca existiu).
Decisão: corrigido nos dois Dockerfiles. Ambos os bugs existiam desde a criação dos Dockerfiles (12/08) e só foram pegos agora porque o gate estava BLOCKED por Docker Desktop offline — reforça a regra "no external verification, no trust".

## D-2026-08-27-5: CI/CD separados — GitHub Actions (CI) + Coolify (CD)
Contexto: D5 original bundlava CI/CD numa coisa só. Usuário pediu separação explícita: local nunca dispara pipeline, push+cloud ativa CI, CD só quando há destino real.
Decisão: GitHub Actions = CI puro (lint/test/build/`docker build`, sempre, sem tocar infra). Coolify = CD (self-hosted na VM `oci-free`, deploy só em merge pra `main`, com rollback/approval). Ver ADR-006 em `infra-platform/docs/explanation/adr/`.

## D-2026-08-27-6: Oracle Cloud Always Free (ARM) como primeiro alvo cloud, antes da AWS
Contexto: nenhum dos 5 projetos gera receita ainda. Usuário quer validar todo o pipeline de deploy sem gastar, e quer portabilidade multi-cloud como objetivo explícito (custo + aprendizado).
Decisão: novo ambiente `oci-free` (Oracle Cloud Always Free, Ampere A1 ARM, 2 OCPU/12GB — reduzido de 4/24 em jun/2026) entra ANTES da AWS no roadmap. AWS continua sendo o destino final (`aws-prod`), mas só quando houver receita/escala que justifique. Mesma imagem Docker roda nos dois — portabilidade real, não teórica. Ver ADR-007.

## D-2026-08-27-7: Terraform Cloud (free) como backend de state, cloud-agnóstico
Contexto: `.tfstate` nunca pode ir pro git; backend específico de cloud (ex: S3) acopla o state a um provider só, contra o objetivo de portabilidade.
Decisão: Terraform Cloud free tier — um workspace por ambiente (`oci-free`, depois `aws-prod`), funciona igual não importa a cloud dos recursos. Ver ADR-008.

## D-2026-08-27-8: Caddy removido do escopo do Batch 2 (adiado pro Track C)
Contexto: Cloudflare Tunnel já resolve TLS/WAF/DDoS de graça, funciona hoje. Caddy local não tem necessidade concreta agora.
Decisão: não implementar Caddy agora. Fica registrado pro Track C (ingress de cloud real). Ver ADR-009.

## D-2026-08-27-9: Prometheus adicionado à stack — gap real achado no Batch 2
Contexto: investigando o Batch 2 (dashboards Grafana), achei que NENHUM Prometheus roda na stack — `/metrics` dos APIs e o exporter do OTEL Collector (`:8889`) não são coletados por ninguém. O dashboard `golden-signals.json` do Batch 1 já assume datasource Prometheus e renderizaria "no data".
Decisão: Prometheus entra na `infra-platform/platform/docker-compose.yml` (self-hosted, mesmo padrão de Vault/OTEL) como pré-requisito do trabalho de dashboards do Batch 2. Ver ADR-009.

## D-2026-08-27-10: Limpeza de organização de pastas — ~1GB de instalação manual removida
Contexto: auditoria encontrou `~/services/platform` (duplicata órfã, dono root, sem nenhuma referência) e `~/projects/services/` com ~1GB de tarballs/binários extraídos manualmente (grafana-v11.1.0, influxdb2-2.7.6, telegraf-1.30.3, mosquitto.deb) — resíduo de `start-microgrow.sh`, um bootstrap manual pré-Docker-Compose, totalmente superado.
Decisão: removidos os ~230MB de tarballs + ~800MB de binários extraídos + `start-microgrow.sh` (confirmado sem nenhuma referência em PM2/compose antes de apagar). `~/services/platform` (root-owned) **não foi possível remover** — sem sudo. Pendência: usuário rodar `sudo rm -rf ~/services` manualmente. `evolution-api` (WhatsApp, ligado ao vetcare) movido de `~/projects/services/evolution/` pra `~/projects/vetcare/infra/evolution/`. Padrão de organização documentado em `infra-platform/docs/reference/repository-layout.md`.

## D-2026-08-27-11: infra-platform commitado + gh CLI instalado (sem sudo)
Contexto: repo `infra-platform` tinha 46 arquivos staged desde 12/08 mas **nunca commitados** — nada estava versionado de fato, apesar do Batch 1 ter reportado "git init + git add -A: PASS". `gh` CLI não estava instalado.
Decisão: commit inicial criado (`b73814f`). `gh` CLI 2.98.0 instalado via binário direto em `~/.local/bin` (sem sudo). Push pro remoto pendente — falta autenticar `gh` (device flow é interativo, aguardando ação do usuário) ou criar o repo manualmente no GitHub.

## D-2026-08-27-12: agentes de IA apontados pro infra-platform como fonte de verdade
Contexto: usuário pediu que os agentes (harness-infra, harness-dev, infra-analyzer) saibam consultar a infra real — tanto pros 4 produtos existentes quanto pra novos — sem precisar reexplicar toda sessão. Repo `agents-harness` (github.com/rastaFul/agents-harness) é o que ele reinstala em máquina nova.
Decisão: `harness-infra.md` ganhou seção "Infra Source of Truth" apontando pra `~/projects/infra-platform/docs/` (ADRs + reference) — lida toda sessão, antes de decidir algo já decidido lá. `infra-analyzer.md` e `harness-dev.md` ganharam referências mais leves (não reportar como "finding" algo que já é decisão documentada; consultar `docker-build-conventions.md` antes de mexer em Dockerfile/CI). `CLAUDE.md` global também. Sincronizado em `~/.claude/` (ativo nesta máquina) e commitado+pushed em `agents-harness` (`bda58dd`) — portátil pra quando trocar de PC.

## D-2026-08-27-13: tudo commitado e versionado — 5 repos + 1 novo (harness-specs)
Contexto: usuário pediu "registre tudo e dê o push". Auditoria achou que `microgrow`, `rastafinancas` e `vetcare` tinham o trabalho do Batch 1 (Dockerfiles, prom-client, GlitchTip, structured /health) nunca commitado, misturado no working tree com WIP de feature do próprio usuário. `~/.specs` (estado cross-repo do harness — STATE/DECISIONS/audit/metrics/specs) nunca tinha sido um repo git.
Decisão: commitado só o que é infra/observability em cada repo (nunca o WIP de feature do usuário — ficou intocado, staged pra ele revisar/commitar depois):
- `microgrow` → `fe04b5c4` (Dockerfiles api/webapp/webapp-sim, prom-client, GlitchTip, /health)
- `rastafinancas` → `3e1ba1c` (Dockerfiles api/web, product-metrics, fix node_modules path)
- `vetcare` → `6737630` (Dockerfile + fix DATABASE_URL build placeholder, move evolution-api)
- `artists-booking` — já estava commitado (outro processo/sessão do usuário, confirmado via `git log`)
- `~/.specs` → **novo repo** `git init` + `github.com/rastaFul/harness-specs` (privado) — primeira vez que esse estado é versionado.
Nota: `vetcare/.gitignore` tem `.env*` genérico, que também ignora `.env.example` (deveria ser commitado como template) — não mexi, fora do escopo pedido, só reportando.

## D-2026-08-27-14: gate Playwright — infra de teste não documentada (fix) + gap real achado
Contexto: usuário perguntou que infra o `harness-dev` usa pra rodar gates Playwright reais, já suspeitando que banco de dados não é "infra direto do projeto". Auditando a skill `playwright-mcp`, confirmei que ela nunca especificava isso — só dizia "app server must be running".
Decisão: formalizado — infra de teste local (banco isolado, `docker-compose.dev.yml` do próprio repo do produto) é responsabilidade do `harness-dev` (sobe/derruba sem spec, é efêmero) e é DIFERENTE da infra compartilhada `infra-platform` (Vault/observabilidade, responsabilidade do `harness-infra`, precisa de spec). Documentado em `playwright-mcp/SKILL.md` (seção "Test Infra") + `harness-dev.md`. Sincronizado e pushed em `agents-harness` (`f29b18b`).
**Gap real encontrado ao verificar (não assumido):** só `vetcare` tem banco de teste isolado (`postgres_test`, porta 5433). `rastafinancas` e `artists-booking` usam SQLite única — dev e teste cairiam no mesmo arquivo, sem isolamento. A skill agora instrui o agente a AVISAR o usuário nesse caso em vez de testar contra o banco de dev. Fica como backlog (precisa spec própria por projeto — não é decisão de infra compartilhada).

## D-2026-08-27-15: consolidação estrutural completa (Platform, Tunnel, .specs)
Contexto: usuário questionou toda a duplicação que eu tinha deixado passar (harness-specs vs agents-harness, services/ vs infra-platform/, .specs em 3 lugares). Investigação confirmou tudo real, não só falta de explicação.
Decisões executadas:
- **Platform stack consolidada**: `services/platform/` (Grafana/InfluxDB/Loki/GlitchTip) mesclado em `infra-platform/platform/docker-compose.yml` junto com Vault/OTEL/Prometheus. Volumes pinados por `name:` explícito nos nomes reais (`platform_*`) — achei 3 gerações de volumes órfãos (`infra_*`, `observability_*`, `platform_*`) de renomes de pasta ao longo do tempo; migração verificada sem perda de dado (Grafana `database:ok`, GlitchTip `_health/:ok`, Prometheus scraping). Bug bônus achado: healthcheck do otel-collector usava `wget`, mas a imagem é distroless (sem shell) — reportava "unhealthy" falso há 2h. Removido, liveness agora é via scrape target do Prometheus. Ver ADR-010.
- **Tunnel migrado**: `services/tunnel/` → `infra-platform/tunnel/`. PM2 `platform-tunnel` re-registrado (delete+start+save) no novo path. Corrigido erro meu: ADR-007/how-to citavam `~/.cloudflared/config.yml` como "o" tunnel — errado, o real sempre foi `services/tunnel/cloudflared/config.yml`. Ver ADR-011.
- **Padrão de segurança confirmado e documentado**: artists-booking/rastafinancas/microgrow já usam proxy server-side (`next.config.js` rewrites `/api/*` → localhost:PORT) — API nunca tem hostname público próprio. vetcare é monolito. MQTT do microgrow foi removido do tunnel deliberadamente (comentário no mosquitto.conf confirma). Ver ADR-011.
- **Bug de produção real achado e corrigido**: `artists.rastaful.dev` retornava 500 — pnpm store corrompido (`ERR_PNPM_MODIFIED_DEPENDENCY`) causando ENOENT em arquivos internos do Next.js no `artists-web`. Fix: `pnpm install --force` + restart. Confirmado voltou a 307 (normal) local e público. NÃO tinha relação com o trabalho de infra de hoje.
- **`.specs` redistribuído**: `harness-specs` (repo criado hoje mais cedo) foi decisão errada — revertida no mesmo dia. Conteúdo cross-repo → `infra-platform/.specs/` (aqui). `microgrow-full-test`/`startup-validation` → `microgrow/.specs/`. `17-contractor-onboarding`/`short-term` (vazados de `~/.specs` E `~/projects/.specs` — dois locais diferentes por engano) → `artists-booking/.specs/`. `clock-of-clocks` (spec órfã, sem repo) → deletado. Ver ADR-012.
- **`~/projects/services/` removido** (ficou vazio após as duas migrações). Repo GitHub `rastaFul/services` mantido intocado (não deletado) — pendente decisão explícita do usuário se quer arquivar/deletar.
- **Pendência do usuário**: `gh auth refresh -h github.com -s delete_repo` + `gh repo delete rastaFul/harness-specs --yes` (token sem escopo pra eu deletar sozinho).
- **Pendência de decisão**: apagar volumes Docker órfãos `infra_*` (41MB influx, 1.2MB grafana, 1.6MB loki) e `observability_*` (79MB glitchtip-db, 284KB loki)? Confirmados sem nenhuma referência em compose files atuais.

## D-2026-08-27-4: vault-init.sh adiado para Batch 3
Contexto: com Docker Desktop de volta, `docker compose up` do platform stack (Vault + OTEL Collector) rodou limpo e `vault status` respondeu (uninitialized, sealed — esperado). O script `vault-init.sh` de fato inicializa o Vault, gerando root token + unseal keys (ação sensível, sem rollback trivial).
Decisão: não executar vault-init.sh como parte do fechamento de gate do Batch 1. Fica como primeira tarefa formal do Batch 3, com spec própria cobrindo AppRole por projeto. Containers vault/otel-collector deixados rodando (isolados, portas só 127.0.0.1) — não há motivo pra derrubar.
