# SPEC: Security Hardening — Fase 1

## Status: DONE — Tasks 1-5 todas executadas (2026-08-28)
## Created: 2026-08-27
## Updated: 2026-08-28 — usuário aprovou execução ("pode executar tudo")
## Owner: rodrigo

---

## Contexto

Auditoria de "comunicação segura entre camadas" (2026-08-27) encontrou 1 achado **crítico** e 3 gaps de médio/baixo risco, todos com dado real (não suposição). Objetivo desta fase: fechar os itens rápidos e de alto retorno. Itens que precisam de investigação mais profunda por produto ficam em `security-audit-auth-session/spec.md`.

## Achados

### 🔴 CRÍTICO — fallback de JWT_SECRET hardcoded em 2 de 4 produtos
- `rastafinancas/apps/api/src/server.ts:30`: `JWT_SECRET ?? 'dev-secret-change-in-production-32chars!!'`
- `artists-booking/apps/api/src/infrastructure/services/jwt.service.ts:15-16`: `JWT_SECRET ?? 'dev-secret'`, `JWT_REFRESH_SECRET ?? 'dev-refresh-secret'`

Hoje o `.env` real de produção **tem** o valor setado (confirmado, não é exploração ativa) — mas o fallback existe no código-fonte, versionado. Se a env var for esquecida em qualquer deploy futuro (novo ambiente, `oci-free`, container recriado sem `.env`), o processo sobe silenciosamente com um segredo público e previsível — qualquer um que leia o repo pode forjar tokens JWT válidos. Não deveria ser possível subir o processo sem a env var real.

### 🟡 CORS: `origin.startsWith()` em vez de match exato
- `artists-booking/apps/api/src/app.ts:66`, `microgrow/api/src/index.ts:56`: `allowedOrigins.some(o => origin.startsWith(o))`
- Risco: `https://artists.rastaful.dev` como allowlist também aceitaria `https://artists.rastaful.dev.evil.com` (prefixo bate, domínio é outro). Baixa probabilidade de exploração hoje (allowlist curta, controlada), mas é um anti-padrão que não deveria compor com nenhuma allowlist gerada dinamicamente no futuro.

### 🟡 CI não tem gate de vulnerabilidade automatizado
`npm audit` já foi rodado manualmente (bom sinal — commit "0 vulnerabilidades" em artists-booking), mas não é step do CI. `trivy` (scan de imagem Docker) está listado como ferramenta do harness mas nunca rodou contra nenhuma das 8 imagens buildadas no Batch 1.

### 🟢 `/metrics` sem autenticação
Hoje é baixo risco (bind `127.0.0.1`, rede Docker isolada). Vira risco real quando o Oracle VM compartilhar rede com Coolify/outros tenants (Fase 1). Resolver antes da migração, não depois.

### 🟢 Vault rodando, zero uso real
Self-hosted, saudável, mas nunca inicializado (`vault-init.sh` adiado, D-2026-08-25-4). Segredos continuam em `.env` estático. Pré-requisito de tudo acima ser feito "direito" (secrets dinâmicos, AppRole por projeto) em vez de paliativo.

---

## Done Criteria

1. `JWT_SECRET`/`JWT_REFRESH_SECRET` (e qualquer outro secret com fallback hardcoded encontrado na auditoria) — processo **falha no boot** (`throw` explícito) se a env var não estiver setada em `NODE_ENV=production`. Fallback de dev só permitido fora de produção, com warning explícito no log.
2. CORS: `origin.startsWith()` → comparação exata (`allowedOrigins.includes(origin)`) nos 2 projetos afetados.
3. CI reusable workflow (ADR 006) ganha steps: `npm audit --audit-level=high` (falha o build em high/critical) + `trivy image` contra a imagem buildada (falha em CRITICAL).
4. `/metrics` protegido — token simples via header (`X-Metrics-Token`) validado no Prometheus scrape config + no endpoint, OU restrito por IP/rede quando possível. Decisão de qual mecanismo: ver Task 4.
5. `vault-init.sh` executado — Vault inicializado, unsealed, AppRole criado por projeto (artists, microgrow, rastafinancas, vetcare). Não migra os secrets ainda (isso é Batch 3 / `security-audit-auth-session`), só deixa Vault pronto para uso.

## Tasks

| # | Task | Repo(s) | Blast radius |
|---|---|---|---|
| 1 | Fix fail-fast em JWT secrets (2 projetos) | artists-booking, rastafinancas | Baixo — só falha se env var já estivesse faltando (não deveria estar em prod) |
| 2 | CORS exact-match | artists-booking, microgrow | Baixo |
| 3 | CI: `npm audit` + `trivy` gates | infra-platform (reusable workflow) + 5 repos | Baixo — só CI, não deploy |
| 4 | Proteger `/metrics` | infra-platform (prometheus.yml) + 3 APIs | Baixo-Médio — decidir mecanismo antes |
| 5 | `vault-init.sh` | infra-platform | Médio — gera root token/unseal keys, ação sensível |

## Decisões (resolvidas na execução, 2026-08-28)

- [x] D1: token compartilhado (`METRICS_TOKEN`, `Authorization: Bearer`) — Prometheus usa `authorization.credentials_file` (padrão nativo, arquivo gitignored `platform/prometheus/metrics_token`), não header customizado (Prometheus não manda headers arbitrários).
- [ ] D2: `vault-init.sh` — em andamento nesta mesma execução (usuário aprovou "tudo").
- [ ] D3: `npm audit` — a decidir quando Task 3 (CI) for implementada.

## Log de Execução (2026-08-28)

- **Task 1 (JWT fail-fast)**: aplicado em artists-booking e rastafinancas. `tsc --noEmit` PASS nos 2. Restart + health check PASS.
- **Task 2 (CORS exact-match)**: aplicado em artists-booking e microgrow. `tsc --noEmit` PASS. Restart + health check PASS.
- **Task 4 (`/metrics` token)**: implementado nos 3 APIs + `prometheus.yml` (`authorization.credentials_file`) + `docker-compose.yml` (mount do token) + `ecosystem.config.js` de cada projeto (forward explícito do `METRICS_TOKEN` — **achado no processo**: nenhum dos 3 confiava só em `.env`; rastafinancas e microgrow tinham allowlist/hardcode que NUNCA repassava o token pro processo real, só artists-api parecia funcionar por um mecanismo implícito do tsx nunca confirmado — resolvido tornando explícito nos 3, mais seguro que depender de comportamento não documentado). Gate final: 403 sem token, 200 com token, nos 3 APIs.
- **Colisão real durante a execução**: outra sessão (Claude Code) estava trabalhando em paralelo no repo `artists-booking` (commits de auditoria visual/UI concorrentes) e sobrescreveu os 3 arquivos que eu tinha acabado de editar (`jwt.service.ts`, `app.ts`, `observability.plugin.ts`, `ecosystem.config.js`) antes de eu commitar. Detectado via nota automática do sistema ("changed on disk since you last read it") + confirmado com `git log`/`git diff`. Reaplicado e commitado imediatamente (`82fa0f8`) para reduzir a janela de colisão. rastafinancas e microgrow não foram afetados (sem sessão concorrente ali).
- **Task 5 (`vault-init.sh`)**: rodei o script — falhou 2x com bugs reais nunca antes exercitados (nunca tinha rodado de verdade): (1) `curl -sf` contra `/v1/sys/health` do Vault, que retorna HTTP não-2xx de propósito pra estados válidos (501 não inicializado, 503 selado) — `-f` tratava isso como falha, loop nunca via o corpo, timeout sempre. (2) volume `platform_vault_data` com dono `root:root` em vez de `vault:vault` (nunca exercitado desde a criação em 12/08) — `operator init` falhava com "permission denied". Ambos corrigidos (`scripts/vault-init.sh`, `chown` no volume). 3ª tentativa: sucesso total — Vault inicializado, unsealed, KV v2 habilitado, AppRole habilitado, policy + AppRole criados pros 4 projetos. Chaves em `~/.vault-init-local` (chmod 600, gitignored, nunca exibidas no chat).
- **Task 3 (CI gates)**: workflow reutilizável criado (`infra-platform/.github/workflows/reusable-ci.yml`) + `ci.yml` chamando ele nos 4 repos de produto (5 apps ao todo — artists tem api+web, rasta tem api+web, microgrow tem api+webapp+webapp-sim, vetcare é 1 só). Precisou habilitar acesso cross-repo (`gh api ... actions/permissions/access`, `access_level=user` — plano gratuito não permite `organization`). **3 bugs reais achados rodando de verdade** (nunca tinha rodado antes, spec nova): tag `trivy-action@0.24.0` não existe (corrigido pra SHA fixo do `v0.36.0` — motivo extra: essa action teve comprometimento de supply-chain documentado em março/2026, SHA pin é mitigação real, não only-hardening); `pnpm/action-setup` com `version:` explícito conflitando com `packageManager` do `package.json` ("Multiple versions of pnpm specified"); `cache-dependency-path` com glob errado (`*.lock*` não bate `pnpm-lock.yaml`/`package-lock.json`), erro fatal que abortava o job antes de rodar lint/tsc/test/audit. Todos corrigidos. **CI agora roda de ponta a ponta e achou 2 problemas reais e pré-existentes em `artists-booking`** (não bugs meus, débito nunca antes visível por falta de CI): CVE crítico `tar@7.5.11` (CVE-2026-59873, DoS, corrigido em 7.5.19, dependência transitiva) e erros `tsc` de tipos implícitos `any` em 2 arquivos. Registrados como achados, não corrigidos nesta spec (fora de escopo — é débito de código do produto, não da infra).

## Fora de Escopo (vira spec própria)

- Auditoria de hash de senha, cookies (`httpOnly`/`secure`/`sameSite`), refresh token por produto → `security-audit-auth-session/spec.md`
- Backup de dados → `backup-strategy/spec.md`
- mTLS entre serviços (só relevante multi-host, Fase 1/Oracle) → decisão de arquitetura, não código ainda
