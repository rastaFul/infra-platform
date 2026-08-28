# Execution Audit — infra-platform

## Session: 2026-08-12

---

## Batch 1 — Parallel (IN_PROGRESS)

### Agent 1: infra-platform-scaffold
- Criando: /home/rodrigo/projects/infra-platform/
- Vault config + HCL policies (4 projetos)
- OTEL Collector config
- ADRs 001-004
- Diátaxis docs
- Grafana dashboards (golden signals)
- Alert rules

### Agent 2: dockerfiles-all
- Fix: artists-api tsconfig noEmit: true → false
- Dockerfiles multi-stage: artists-api, artists-web, microgrow-api, microgrow-webapp, microgrow-webapp-sim, rastafinancas-api, rastafinancas-web, vetcare

### Agent 3: health-metrics-otel
- /health endpoint: artists-api, microgrow-api, rastafinancas-api
- /metrics (prom-client): artists-api, microgrow-api (rastafinancas já tem)
- GlitchTip wiring: artists-api, microgrow-api
- OTEL SDK: todos os APIs

---

## Session: 2026-08-25 — Resume + Recovery + Batch 1 Gate Closure

### Step 1: Investigate/restore running stack
- `pm2 list`: 0/10 processos (daemon frio, sem persistência pós restart WSL2)
- `pm2 resurrect` (dump.pm2, 2026-06-13): PASS — 10/10 online
- Docker CLI: FAIL — `/usr/bin/docker` → I/O error (mount `/mnt/wsl/docker-desktop` órfão, Docker Desktop não rodando no host Windows). Não corrigível via shell WSL — **ação manual do usuário necessária**.
- artists-api: crash loop detectado pós-resurrect (↺178) — `MODULE_NOT_FOUND: prom-client`. Causa raiz: dependência declarada em package.json pelo Agent 3 (health-metrics-otel, 08-12) nunca instalada — gate `pnpm install` pulado na sessão anterior.
  - Fix: `npx pnpm@9 install --filter api...` (pnpm 7.1.7 do projeto está quebrado contra o registry atual: `ERR_INVALID_THIS`)
  - Status: RESOLVED — health:200, metrics:200, restart count estável

### Step 2: Fechamento Batch 1 — gates re-executados (pulados na sessão 08-12)

#### Agent 2: dockerfiles-all
- Dockerfiles presentes (9 arquivos, 8 serviços): PASS
- artists-api tsconfig noEmit: false: PASS (confirmado)
- docker compose config: N/A — Docker CLI indisponível (ver acima)
- docker compose YAML syntax (python yaml.safe_load, offline): PASS (5/5 arquivos)
- docker build: BLOCKED (Docker CLI indisponível)
- Status: DONE (parcial — pendente docker build quando Docker Desktop voltar)

#### Agent 3: health-metrics-otel
- tsc --noEmit artists-api: FAIL → 2 erros (Sentry API v10 incompatível + branch 'degraded' inalcançável) → FIXED → PASS
- tsc --noEmit microgrow-api: FAIL → 1 erro (mesmo padrão Sentry) → FIXED → PASS
- tsc --noEmit rastafinancas-api: PASS (sem alterações necessárias)
- /health todos os 3 APIs: PASS (200)
- /metrics todos os 3 APIs: PASS (200)
- Status: DONE

### Gates pendentes (bloqueados por Docker Desktop offline)
- docker build: todos os Dockerfiles
- docker compose config (client real)
- vault status / vault-init.sh

### Overall Batch 1 Status: DONE (com ressalva: docker build gate pendente até Docker Desktop reiniciar)

---

## Session: 2026-08-27 — Batch 1 Gate Closure (Docker Desktop reativado pelo usuário)

### Docker Desktop: PASS
- `docker info`: server 29.6.2 respondendo, 20 containers parados / 0 rodando (esperado, PM2 ainda no comando)
- Nota: `docker network ls`/`docker network inspect` sem redirect para arquivo retornam stdout vazio neste ambiente (hook de filtragem de output interceptando indevidamente). Workaround: redirecionar para arquivo. Não afeta `docker build`/`docker compose`/`docker ps`.

### Gate: docker build (8 serviços) — 3 rounds até PASS total
**Round 1** (contexto de build errado nos 4 apps de monorepo + bug real em 3):
- microgrow-api: PASS | microgrow-webapp: PASS | microgrow-webapp-sim: PASS
- artists-api: FAIL (contexto errado) | artists-web: FAIL (contexto errado)
- rastafinancas-api: FAIL (contexto errado) | rastafinancas-web: FAIL (contexto errado)
- vetcare: FAIL (bug real: `DATABASE_URL` não setado quebra `next build` ao coletar page data de rota que importa Prisma client eagerly)

**Round 2** (contexto corrigido p/ raiz do monorepo + fix vetcare):
- rastafinancas-api: PASS | vetcare: PASS (fix: `ENV DATABASE_URL=postgresql://build:build@localhost:5432/build_placeholder` no build stage — placeholder nunca conecta de fato, page data collection só precisa do client gerado)
- artists-api: FAIL (tsc: `tsconfig.base.json` nunca copiado pro build context — cai nos defaults do TS sem `esModuleInterop`/`target ES2022`, quebra tipos de pino/google-auth-library)
- artists-web: FAIL (`ERR_PNPM_IGNORED_BUILDS` — `corepack prepare pnpm@latest` puxou pnpm 10+, que bloqueia scripts de instalação de esbuild/unrs-resolver por padrão sob `--frozen-lockfile`)
- rastafinancas-web: FAIL (Dockerfile copiava `/app/apps/web/node_modules` no runtime stage, mas `npm ci --workspaces` hospeda tudo em `/app/node_modules` — path nunca existiu)

**Round 3** (fixes aplicados — 3º retry, limite do harness):
- artists-api: fix — `COPY tsconfig.base.json ./` adicionado + `corepack prepare pnpm@9` (pin, consistente com D-2026-08-25-2) → PASS
- artists-web: fix — `corepack prepare pnpm@9` pin (2 stages) → PASS
- rastafinancas-web: fix — runtime stage copia `/app/node_modules` (raiz) em vez de `/app/apps/web/node_modules` → PASS

**Resultado final: 8/8 PASS** (gate-artists-api, gate-artists-web, gate-microgrow-api, gate-microgrow-webapp, gate-microgrow-webapp-sim, gate-rastafinancas-api, gate-rastafinancas-web, gate-vetcare — todos tag `:test`)

### Gate: docker compose config — PASS (5/5)
- infra-platform/platform/docker-compose.yml: PASS
- microgrow/infra/docker-compose.yml: PASS
- services/platform/docker-compose.yml: PASS
- artists-booking/docker-compose.dev.yml: PASS (precisa `-f` explícito, sem docker-compose.yml default)
- vetcare/docker-compose.dev.yml: PASS (idem)

### Gate: platform stack (Vault + OTEL Collector) — PASS
- `docker compose up -d` em infra-platform/platform/: platform_net (external, já existia) — sem erro
- platform-vault: healthy | `vault status`: reachable, `initialized:false, sealed:true` (estado esperado de primeiro boot)
- platform-otel-collector: metrics endpoint (`:8888/metrics`) respondendo OK
- **Decisão: NÃO rodar vault-init.sh nesta sessão** — inicialização gera root token + unseal keys (ação sensível, escopo próprio do Batch 3). Containers deixados rodando (isolados em platform_net, portas só em 127.0.0.1).

### Overall Batch 1 Status: **DONE — todos os gates fechados, sem ressalvas pendentes**

