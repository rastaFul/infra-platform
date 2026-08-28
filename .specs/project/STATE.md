# STATE

## Session: Infra Strategy — Phase 0 Execution
## Status: EXECUTING
## Last updated: 2026-08-25

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
- [ ] docker compose up platform (Vault + OTEL Collector)
- [ ] vault-init.sh — AppRole por projeto
- [ ] Migração PM2 → Docker Compose (1 serviço por vez)
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
