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

## D-2026-08-27-16: descoberta de infra tornada operacional nos agentes (não só documentada)
Contexto: usuário confirmou limpeza (`~/services` deletado, volumes órfãos removidos) e pediu explicitamente que os agentes "saibam enxergar as infras independente do projeto" e ".specs deve ser no projeto que eu estiver trabalhando, pra evitar bagunça de novo".
Decisão: `harness-infra.md`, `harness-dev.md`, `infra-analyzer.md` e `CLAUDE.md` (repo `agents-harness`) ganharam regra 0 executável: `.specs/` sempre = `git rev-parse --show-toplevel` do diretório atual; se não estiver dentro de um repo, PARA e pergunta qual projeto, nunca assume home/pasta pai. `infra-platform` deixou de ser path hardcoded (`~/projects/infra-platform/`) e passou a ser descoberto dinamicamente como diretório irmão do repo atual (`$(dirname $(git rev-parse --show-toplevel))/infra-platform`) — funciona independente de qual projeto ou máquina. Sincronizado em `~/.claude/` + commitado/pushed em `agents-harness` (`18cc191`).

## D-2026-08-27-17: Ansible em vez de Vagrant pro ambiente de dev WSL2/Linux/Mac
Contexto: usuário já versiona ambiente via git+Vagrant pra portar entre máquinas, perguntou o que fazer especificamente no WSL2 e se dá pra usar só Ansible.
Decisão: sim — WSL2 já é uma VM (Hyper-V), rodar Vagrant dentro dele seria virtualização aninhada sem ganho (confirmado: nenhum provider instalado). Ansible cobre dotfiles+pacotes sem precisar de VM, roda idêntico em WSL2/Linux/Mac, e reaproveita depois pra configurar VMs reais (Oracle) — Terraform provisiona, Ansible configura, combinação padrão. Spec: `features/dev-environment-ansible/spec.md`. Pendente: usuário mandar o conteúdo do repo Vagrant existente antes de detalhar tasks.

## D-2026-08-27-18: achado crítico — JWT_SECRET com fallback hardcoded (2 produtos)
Contexto: auditoria rápida de CORS (pedida pelo usuário como item barato da lista de segurança) encontrou `rastafinancas/apps/api/src/server.ts:30` e `artists-booking/apps/api/src/infrastructure/services/jwt.service.ts:15-16` com fallback de secret JWT hardcoded no código-fonte (`'dev-secret-change-in-production-32chars!!'`, `'dev-secret'`). `.env` real de produção tem valor setado (não é exploração ativa hoje), mas é uma bomba-relógio — qualquer deploy futuro sem a env var sobe silenciosamente com segredo público/previsível.
Decisão: registrado como item CRÍTICO na spec `features/security-hardening-phase1/spec.md`, task 1 (fail-fast no boot se a env var real não estiver setada em produção). NÃO corrigido ainda — spec aguarda aprovação antes de execução (toca código de auth de 2 produtos).

## D-2026-08-27-19: PROJECT.md e ROADMAP.md corrigidos/criados
Contexto: `PROJECT.md` tinha conteúdo de outro projeto (Clock of Clocks) parado lá por acidente de sessão — nunca foi sobre o infra-platform de fato. `ROADMAP.md` nunca existiu.
Decisão: `PROJECT.md` reescrito (visão, objetivos, produtos servidos, stack, repos). `ROADMAP.md` criado do zero, consolidando Fase 0 (DONE) até Fase 2+ (AWS), incluindo as novas frentes de segurança e ambiente de dev.

## D-2026-08-27-20: dev-environment-ansible — sem legado, começa do zero
Contexto: perguntei se havia repo Vagrant pessoal existente antes de detalhar tasks (D1 da spec). Usuário confirmou: só existe na empresa (fora de escopo/acesso), nada pessoal ainda.
Decisão: spec `dev-environment-ansible` promovida de DRAFT pra APPROVED — D1 e D3 resolvidos (sem legado, sem migração gradual, Ansible desde o início). Tasks detalhadas escritas (7 tasks: repo, roles dotfiles/packages/agents-harness/credentials-check, README, teste de idempotência). Falta só D2 (repo público ou privado) — assumindo privado por padrão até confirmação, não vou criar público sem sinal explícito.

## D-2026-08-27-21: repo `dev-environment` criado, privado, gates rodados
Contexto: D2 (visibilidade) resolvida pelo usuário — privado. Spec `dev-environment-ansible` já estava APPROVED com tasks detalhadas.
Decisão: repo criado (`github.com/rastaFul/dev-environment`, privado). Ansible instalado sem sudo (`pip3 install --user`) — versão 2.13.13 (Python 3.8 desta máquina não suporta ansible-core mais novo). 4 roles: `credentials-check` (só verifica, nunca gera segredo), `packages` (apt/homebrew condicional), `dotfiles` (`.zshrc`/`.gitconfig` reais desta máquina como base, com backup antes de sobrescrever), `agents-harness` (clone + sync pra `~/.claude`).
Gates rodados: `--syntax-check` PASS. `ansible-lint` **não rodou** — exige Python 3.9+, esta máquina tem 3.8 (limitação de ambiente, não do código — rodar numa máquina com Python mais novo antes de confiar cegamente). `--check --diff` (dry-run completo, pulando tag `packages` por falta de sudo): PASS, 0 failed, 21 ok, 7 changed.
**Achado real durante o dry-run**: `~/.claude/skills/` e `~/.claude/steering/` estavam com drift em relação ao `agents-harness` — eu só sincronizei arquivos específicos manualmente em sessões anteriores, não as pastas inteiras. O playbook, se rodado de verdade (não `--check`), fecha esse gap. Não rodei de verdade ainda — só dry-run, aguardando o usuário decidir se quer aplicar agora.
`darwin.yml` escrito contra documentação do módulo Homebrew, nunca testado de verdade (sem Mac disponível ainda) — validar no primeiro Mac real.

## D-2026-08-28-1: dev-environment aplicado de verdade — 2 bugs reais achados e corrigidos
Contexto: usuário aprovou "executar tudo". Rodei o playbook pra valer (não `--check`).
Decisão: achados 2 bugs reais só possíveis de pegar em execução real (dry-run não pega): (1) templates `zshrc.j2`/`gitconfig.j2` tinham a linha `ansible_managed` sem prefixo `#` — quebrou o `.gitconfig` de verdade (`fatal: bad config line 1`, todo comando git parou de funcionar até eu restaurar do backup automático) e teria feito o zsh tentar "rodar" o texto como comando toda sessão nova. (2) módulo `ansible.builtin.git` bateu bug real do ansible-core 2.13.13 contra a versão do git desta máquina. Ambos corrigidos, revalidado (`--check` + apply real, RC=0), backup automático confirmado funcional na prática (não só teórico). `~/.claude/skills`/`steering` drift fechado. Commit `00a1ff3`.

## D-2026-08-28-2: security-hardening-phase1 — Tasks 1,2,4 executadas
Contexto: usuário aprovou "pode executar tudo".
Decisão: JWT fail-fast (artists-booking, rastafinancas), CORS exact-match (artists-booking, microgrow), `/metrics` protegido por token Bearer nos 3 APIs (não IP — achado real: tráfego via `host.docker.internal` do Prometheus é NAT'd pra `127.0.0.1` no WSL2/Docker Desktop, allowlist de IP nunca bloqueou de verdade). Achado extra: nenhum dos 3 `ecosystem.config.js` repassava env vars novas automaticamente — rastafinancas/microgrow tinham allowlist explícita sem `METRICS_TOKEN`, microgrow nem carregava `.env` (tudo hardcoded). Corrigido nos 3, explícito.
**Colisão real**: sessão paralela (outro Claude Code) trabalhando em `artists-booking` (auditoria visual/UI) sobrescreveu meus 3 arquivos editados antes do commit. Detectado via aviso automático do sistema, reaplicado, commitado rápido (`82fa0f8`) pra reduzir janela. rastafinancas/microgrow não afetados. Lição: quando há sessões concorrentes no mesmo repo, commitar mais frequentemente reduz risco de perda.

## D-2026-08-28-3: security-hardening-phase1 fechada — Tasks 3 e 5 completas
Contexto: continuação de D-2026-08-28-2, Tasks 1/2/4 já feitas.
Decisão: **Task 5 (vault-init.sh)** — 2 bugs reais achados (curl -f contra endpoint 501/503-por-design; volume root-owned) e corrigidos. Vault totalmente inicializado: KV v2, AppRole, policy+role pros 4 projetos. Chaves protegidas, nunca expostas no chat. **Task 3 (CI)** — reusable workflow criado, acesso cross-repo habilitado via API (`access_level=user`, plano free não permite `organization`), 3 bugs reais achados e corrigidos (tag trivy inexistente → SHA pin, motivado também por compromisso de supply-chain documentado da action em março/2026; conflito pnpm version vs packageManager; glob de cache-dependency-path errado, fatal). CI rodando de ponta a ponta agora, achou 2 problemas reais e pré-existentes em artists-booking (CVE crítico `tar`, erros `tsc`) — registrados como backlog do produto, não corrigidos aqui (fora do escopo de infra).
Spec `security-hardening-phase1`: status DONE.

## D-2026-08-28-4: security-audit-auth-session — investigação concluída
Contexto: usuário pediu pra seguir com segurança; sub-agentes especializados (`infra-analyzer`/`code-analyzer`) indisponíveis nesta sessão — investigação feita diretamente por mim (leitura, sem gate, matching regra de quick-mode read-only).
Decisão: auditados os 4 produtos. `rastafinancas` é o mais maduro (rate limit por rota já correto, `secure` condicional a produção, bcrypt 12 rounds). `artists-booking` tem boa arquitetura de refresh token (rotação + revogação) mas 2 gaps reais: sem rate limit específico em `/login`/`/register` (HIGH — brute-force), cookie de refresh sem `secure` (MEDIUM — não explorável hoje pq é tudo localhost atrás do tunnel, mas vira problema real no Oracle multi-host). `microgrow` não tem auth de usuário (só sensor/API). `vetcare` delega tudo pro NextAuth+Google (sem senha armazenada, sem superfície de auth custom). Nenhuma correção aplicada ainda — por design da spec (não misturar leitura com escrita sem aprovação item a item, lição do achado do JWT_SECRET). Detalhe completo com evidência arquivo:linha em `security-audit-auth-session/spec.md`.

## D-2026-08-28-5: achados de security-audit-auth-session delegados pro harness-dev via spec no produto
Contexto: usuário perguntou se fazia sentido criar spec dentro do repo do produto (artists-booking) em vez de eu corrigir agora, pro `harness-dev` pegar depois. Confirmei que sim — são fixes de código de app (rate limit, cookie, bcrypt), escopo do harness-dev, não do harness-infra.
Decisão: criada `artists-booking/.specs/features/21-security-hardening/spec.md` (Status: APPROVED, pronta pro harness-dev executar com TDD quando o usuário pedir). Só esse 1 arquivo foi adicionado/commitado no repo — o repo está em modo autônomo ativo (Feature 20, outra sessão), evitei tocar em qualquer outro arquivo pra não repetir a colisão de hoje mais cedo. Nenhum código corrigido — fica pro harness-dev.

## D-2026-08-28-6: backup-strategy executada — local ativo, R2 pronto mas desativado (não gastar)
Contexto: usuário confirmou D1 (R2)/D2 (diário)/D3 (começar agora local), mas pediu explicitamente pra não gastar dinheiro ainda — R2 exige cadastrar forma de pagamento na Cloudflare mesmo dentro do free tier.
Decisão: `scripts/backup.sh` escrito e rodado de verdade (não só sintaxe) — SQLite (Python stdlib `sqlite3`, CLI não instalado nesta máquina), Postgres (achou `vetcare-postgres-1` parado, subiu como efeito colateral — resolve gap operacional que nem estava sendo procurado), 4 volumes Docker, chaves do Vault. Restore testado de verdade (rastafinancas: 9 tabelas, tamanho idêntico). 1 bug real corrigido (`rotate_weekly` com `find`+`set -e`+`pipefail` derrubando o script). Upload pro R2 está **codificado mas inativo** — só ativa se as env vars `R2_*` existirem, documentado em `docs/how-to/setup-r2-backup-destination.md`, nada criado/cobrado na Cloudflare. Cron configurado (`crontab -l` tem a entrada), mas o daemon `cron` não roda por padrão no WSL2 — ativar precisa de `sudo service cron start` (senha que esta sessão não tem, ação do usuário).

## D-2026-08-28-7: migração de segredos .env → Vault KV v2 (AppRole)
Contexto: usuário aprovou 3 passos sem custo; este é o 1º — Vault estava inicializado desde ontem mas ninguém usava.
Decisão: **Vault vira fonte canônica, `.env` continua sendo o que a app lê em runtime** (zero mudança de código nas 4 apps, zero acoplamento do boot ao Vault estar de pé — decisão deliberada pra essa escala, não é "dynamic secrets" de verdade). 3 scripts novos: `vault-generate-approle-creds.sh` (gera role_id/secret_id, salva local chmod 600, nunca no git), `vault-push-env.sh` (migração one-time, .env real → Vault), `vault-sync-env.sh` (pull Vault → .env, uso recorrente em rotação/máquina nova). Migrados os 4 projetos (14/23/8/19 chaves). **Bug real achado rodando de verdade**: heredoc bash não-quotado reinterpretava `$`/backtick dentro de valores de segredo antes do Python ver — quebrou silenciosamente 2 dos 4 projetos (os que tinham esses caracteres em algum segredo real), os outros 2 "passaram" por sorte de não ter. Corrigido (arquivo temp + heredoc quotado). Revalidado: os 4 batem byte-a-byte com o `.env` original. Procedimento documentado em `docs/how-to/vault-secrets-workflow.md`.

## D-2026-08-28-8: Batch 2 — dashboards e docker-compose já estavam quase todos feitos
Contexto: 2º dos 3 passos aprovados. Fui verificar o estado real antes de criar trabalho novo.
Decisão: **docker-compose por projeto com rede isolada já estava adequado** — artists-booking (`artists_net` explícita), microgrow (própria), rastafinancas (não precisa, SQLite puro), vetcare (rede default do Compose, isolada na prática, só não nomeada explicitamente — LOW, cosmético, não vale o esforço de mudar agora). **Dashboards golden signals**: `golden-signals.json` (criado no Batch 1, órfão até ontem por falta de Prometheus) já cobre artists-booking e rastafinancas automaticamente via `$service` — confirmei com query real no Prometheus (`sum(rate(http_requests_total...))` retornando dado de artists-api e microgrow-api). Achado real restante: **vetcare é o único dos 4 sem `/metrics`** — spec criada e delegada pro harness-dev (`vetcare/.specs/features/observability-metrics/spec.md`), mesmo padrão de delegação do achado de segurança de ontem.

## D-2026-08-28-9: módulo Terraform oci-compute escrito (3º passo aprovado)
Contexto: código puro, não precisa da conta Oracle/Terraform Cloud existir pra ser escrito — só pra aplicar.
Decisão: `terraform/modules/oci-compute/` (VCN, subnet, security list só-SSH — nenhuma porta de app, Cloudflare Tunnel é outbound-only mesma lógica do ADR-011 aplicada na VM — instância Ampere A1 ARM 2 OCPU/12GB conforme ADR-007, cloud-init instala Docker+Coolify). `environments/oci-free/` com backend Terraform Cloud (`cloud {}` block, ADR-008). Instalei Terraform 1.9.8 (o do sistema, 1.4.2, é velho demais pro `cloud` block). Gates rodados de verdade: `init` (baixou provider `oracle/oci` 6.37.0), `validate` PASS, `fmt` PASS (corrigiu 2 arquivos). `plan` não roda — precisa do workspace Terraform Cloud existir, teto do testável até as contas serem criadas.
**Bug real achado no processo**: `.gitignore` só cobria layout flat antigo (`terraform/.terraform/`), não a nova estrutura por-ambiente (`terraform/environments/oci-free/.terraform/`) — ~100MB+ de binário de provider quase foi commitado. Corrigido com padrões `**/` recursivos. Também corrigido: `.terraform.lock.hcl` estava sendo ignorado por engano (deveria ser commitado, igual `package-lock.json`). Removidos os 3 `.tfvars` flat antigos (AWS placeholder, nunca usados), estrutura agora bate com o que `docs/reference/terraform-modules.md` já documentava.

## D-2026-08-28-10: tunnel remotely-managed — 502 real em produção, corrigido parcialmente, 1 passo manual pendente
Contexto: retomando `local-boot-persistence` após o notebook travar. A migração do `platform-tunnel` (PM2→Docker, última peça da Frente B) já estava tecnicamente pronta (container `Up`, config local correta) mas ninguém tinha validado as 6 URLs públicas de ponta a ponta antes do crash — regra "no external verification, no trust" pegou um incidente real que passaria despercebido.
Decisão/achados:
- **502 real confirmado** nas 6 rotas públicas via curl direto (gate externo, não assumido).
- Causa raiz não é rede/IPv6 (isso foi uma pista falsa que investiguei e descartei com evidência: dual-stack `host.docker.internal` existe e afeta o dial do cloudflared — bug conhecido `cloudflare/cloudflared#811` — mas mesmo pinando IP literal `192.168.65.254` no `config.yml` local, o log do container mostrou `originService=http://localhost:3004` em produção, provando que o `config.yml` local **não é usado para roteamento** — este tunnel é gerenciado remotamente pelo dashboard Cloudflare Zero Trust, que ainda aponta pro `localhost:PORT` de antes da containerização.
- Tentei corrigir via API Cloudflare (`CLOUDFLARE_API_TOKEN` já existente em `tunnel/.env`, usado hoje só pro R2) — `GET /accounts` retornou vazio, token sem escopo de conta pra editar tunnel. **Não deu pra corrigir programaticamente.**
- **Ação manual do usuário — CONCLUÍDA 2026-08-29**: painel real era **Networks → Tunnels → rastafinancas → "Published application routes"** (não "Hostname routes" — nome da aba diferente do que eu tinha suposto, mas confirma a hipótese remotely-managed). As 6 rotas tinham `http://localhost:PORT` — porta certa, host errado. Usuário editou pra `http://host.docker.internal:PORT` (recomendação final, não o IP literal — ver correção abaixo). Validado com curl real: 6/6 sem 502 (307/302 normais). Também corrigi a config local (`tunnel/cloudflared/config.yml` + `sysctls: net.ipv6.conf.all.disable_ipv6=1` no `docker-compose.yml`) pro mesmo padrão, testado e comprovado que resolve o dial-bug do cloudflared (IPv6 dual-stack) isoladamente antes de recomendar — evita depender do IP fixo `192.168.65.254` (Docker Desktop gateway, não garantido estável entre upgrades), que era minha primeira sugestão e o usuário corretamente questionou.
- 2 bugs reais adicionais encontrados e corrigidos nesta investigação: `~/.pm2/dump.pm2` tinha entrada órfã `platform-tunnel` (risco de segundo cloudflared concorrente num próximo `pm2 resurrect`) — limpo. `vetcare/Dockerfile` HEALTHCHECK batia em `/` (redireciona pra URL pública via NextAuth, dependia do tunnel pra reportar saúde de um container local) — corrigido pra `/api/health`, rebuild feito.
- `wsl-boot.sh`: `pm2 resurrect` removido (obsoleto, D4 completo — nada mais roda em PM2), `service cron start` adicionado (fecha item do Done Criteria desta spec).
Ver spec `features/local-boot-persistence/spec.md`, execution.md sessão "resume after notebook crash".

## D-2026-08-29-1: observability-promtail-docker — 4 Promtails migrados, 2 bugs reais achados
Contexto: usuário aprovou D1 (restartar rastafinancas e validar de verdade)/D2 (escopo total, incluir vetcare/artists-booking)/D3 (replicar padrão `docker_sd_configs` do microgrow).
Decisão/achados:
- **rasta-telegraf 403 em `/metrics`**: token Bearer de `security-hardening-phase1` (2026-08-28) nunca foi propagado pro telegraf, que ficou 403 silencioso desde então. Corrigido com `bearer_token_string` + `METRICS_TOKEN` no env.
- **4 Promtails migrados de arquivo (`/pm2*logs/*.log`, morto desde a migração PM2→Docker) pra `docker_sd_configs`**: rastafinancas e microgrow reescritos, vetcare e artists-booking criados do zero (nunca tiveram).
- **Bug real sério**: filtro `name: vetcare` sem âncora regex fazia *substring match*, capturando `vetcare-postgres-1`, `vetcare-postgres_test-1` e **o próprio `vetcare-promtail`** — self-scraping (promtail lendo os próprios logs de volta). Resultado: zero dado chegava no Loki. Corrigido com `^vetcare$` e aplicado como hardening preventivo (mesma classe de risco) nos outros 3, mesmo sem bug confirmado neles.
- Validado com gate externo real: `promtail -check-syntax` 4/4, `docker compose config` 4/4, contagem de discovery batendo exato (2/6/1/2), e query real na API do Loki confirmando linhas novas chegando (não só "container Up") pros 4.
Ver `.specs/audit/execution.md` e `features/observability-promtail-docker/spec.md` (DONE).

## D-2026-08-29-2: Caddy preparado (não ativo) + vetcare rede nomeada explicitamente
Contexto: discussão com usuário sobre K8s vs Compose (respondida via ADR-001, já existente) e sobre precisar de reverse proxy quando/se o Cloudflare Tunnel sair do caminho (pergunta legítima de quem geriu EC2+bash e quer "gestão de verdade" sem overhead de cluster). `ADR-009` já tinha essa revisão prevista ("revisit only if a concrete need appears"), nunca escrita.
Decisão: `infra-platform/ingress/caddy/` criado com Caddyfile+compose+README, explicitamente **não ativo** (zero referência em `cloud-init.yaml.tpl` ou qualquer path de provisionamento real), alvos espelhando o `tunnel/cloudflared/config.yml` atual pra ativação futura ser troca de mecanismo, não redesign. `caddy validate` PASS. ADR-009 atualizada com nota cruzada.
`vetcare/docker-compose.dev.yml`: rede default renomeada pra `vetcare_net` explícito (convenção dos outros 3 produtos). Achado real na aplicação: recriar a rede de containers já rodando deixou o relay de porta host→container quebrado no Docker Desktop/WSL2 (sintoma de infra, não do meu compose) — resolvido com `down` completo + `up` em vez de só recriar. Validado local e público (tunnel) depois do fix.

## D-2026-08-29-3: bug crítico de produção em artists-booking (registro quebrado) — achado pelo harness-dev, corrigido pelo harness-infra
Contexto: agente `harness-dev` (sessão paralela, auditoria de UX em `artists-booking`) rodou a suíte Playwright existente como pré-requisito antes de acionar o `ux-journey-judge`, achou 6/29 testes falhando por uma causa raiz única de infra (não UX) e escalou corretamente em vez de tentar corrigir fora do próprio escopo.
Decisão/ação: verificado independentemente (não confiei no relato sozinho) — `POST /api/v1/auth/register` de fato 500 real em produção, `"attempt to write a readonly database"`. Causa: `apps/api/prisma` bind-mounted do host (dono uid 1000) vs container rodando como `appuser` (uid 1001, de um endurecimento de segurança anterior) — regressão da migração PM2→Docker, nunca exercitada até agora (o Playwright funcional não tinha rodado desde a migração). Corrigido em 2 camadas: (1) fix imediato via `docker exec -u root` chown + restart, validado com o request real; (2) fix permanente — `docker-entrypoint.sh` que corrige a permissão em todo boot antes de dropar privilégio pra `appuser` via `su-exec`, testado de verdade simulando um clone novo (reset de dono + recreate do zero, self-heal confirmado, não assumido). `docker build` PASS. Commitado só os 2 arquivos tocados, sessão paralela do harness-dev preservada intacta. Ver `.specs/audit/execution.md`.

## D-2026-08-27-4: vault-init.sh adiado para Batch 3
Contexto: com Docker Desktop de volta, `docker compose up` do platform stack (Vault + OTEL Collector) rodou limpo e `vault status` respondeu (uninitialized, sealed — esperado). O script `vault-init.sh` de fato inicializa o Vault, gerando root token + unseal keys (ação sensível, sem rollback trivial).
Decisão: não executar vault-init.sh como parte do fechamento de gate do Batch 1. Fica como primeira tarefa formal do Batch 3, com spec própria cobrindo AppRole por projeto. Containers vault/otel-collector deixados rodando (isolados, portas só 127.0.0.1) — não há motivo pra derrubar.

## D-2026-09-01-1: artists-booking product-health dashboard + alertas (Spec 53 delegada) + bug crítico de provisioning de alerta corrigido
Contexto: artists-booking em beta com usuários reais, dono do produto pediu visibilidade real no Grafana compartilhado. Spec 53 (artists-booking) delegou o lado infra-platform pra harness-infra: dashboard + alertas seguindo o padrão de microgrow/rastafinancas, consumindo métricas Prometheus que outra sessão paralela está instrumentando no apps/api (não tocado aqui).
Decisão/achados:
- Criado provider `artists-booking` em `dashboard.yml`, dashboard `platform/dashboards/artists-booking/product-health.json` (9 painéis: funil, taxa de busca-sem-resultado, visible_ratio, with_location_ratio/completeness, erro 5xx por rota, real vs demo).
- **Achado crítico, não estava no escopo original mas bloqueava o próprio objetivo do task**: ao tentar verificar externamente que os alertas carregavam de verdade (protocolo "no external verification, no trust"), descoberto que `alerting/rules/*.yaml` (padrão usado por microgrow.yaml e rastafinancas.yaml, que eu deveria replicar) nunca funcionou — Grafana não recursa em subdiretórios de provisioning de alerting (bug conhecido grafana/grafana#53294), e uma subpasta dentro de `alerting/` quebra o provisioning inteiro silenciosamente. `docker logs` confirmou `states=0` em todo restart desde 2026-08-29. Ou seja, TODOS os alertas de microgrow e rastafinancas estavam inertes há dias, ninguém sabia.
- Corrigido pra todos os 3 projetos: arquivos movidos de `alerting/rules/*.yaml` pra `alerting/*.yaml` (flat, mesmo nível de contact-points.yaml/notification-policy.yaml). Resultado real pós-fix: 0 -> 24 alert rules carregadas (6 microgrow + 6 rastafinancas + 3 novas artists-booking, resto pré-existente). Verificado via `GET /api/v1/provisioning/alert-rules`, não assumido.
- 3 alertas novos `artists-booking.yaml` (Prometheus/PromQL — primeiro rule file do repo usando datasource Prometheus em vez de InfluxDB/Flux, já que artists-api usa prom-client): busca-sem-resultado >90%/15min (crítico), erro 5xx em /register >5%/5min (crítico), queda de visible_ratio >20% vs média 1h (warning, heurística). Todos com `noDataState: OK`/`execErrState: OK` explícito — decisão deliberada porque as métricas de produto ainda não existem em produção (spec 53 ainda sendo implementada em paralelo no apps/api); sem isso o default (NoData->Alerting) dispararia notificação crítica falsa assim que o achado de SMTP abaixo fosse corrigido.
- **Achado secundário, fora de escopo, registrado não corrigido**: SMTP (Gmail) do canal `platform-warning`/`platform-critical` está com credencial inválida (530 5.7.0 Authentication Required) — só descoberto porque os alertas passaram a ser avaliados de verdade pela primeira vez. Precisa de app password do Gmail ou troca de provedor SMTP; decisão do usuário.
- Verificação externa completa: `docker compose config` PASS, `GET /api/health` (Grafana) ok a cada restart, dashboard confirmado via `GET /api/search`+`GET /api/dashboards/uid/...` (9 painéis), alertas confirmados via `GET /api/v1/provisioning/alert-rules`. Nenhum outro serviço do compose depende de `grafana` — restart sem risco de cascata, confirmado antes de agir. Detalhe completo em `.specs/audit/execution.md`.

## D-2026-09-08-1: branch principal padrão `main` em vez de `master` — convenção pra todos os repos
Contexto: `infra-platform` usava `master` (herdado, nunca decidido). Usuário pediu a troca neste
repo e que vire padrão pra todos os projetos, não uma decisão isolada.
Decisão: `main` é a branch principal padrão daqui pra frente, em todo repo (existentes e novos).
Ação executada aqui: pré-checagem real (sem PR aberto, sem branch protection, sem workflow/doc
referenciando `master` como branch — só falso-positivo de `sqlite_master` em
`restore-from-backup.md`, não é git) → `git branch -m master main` → `git push -u origin main` →
`gh repo edit --default-branch main` → `git push origin --delete master`. Verificado via
`git branch -a` (só `main` local+remoto) e `gh repo view --json defaultBranchRef` (`main`
confirmado no GitHub). Ver ADR-013.
Escopo desta sessão: só `infra-platform` foi renomeado agora. `artists-booking`, `microgrow`,
`rastafinancas`, `vetcare` continuam em `master` até serem tocados numa sessão futura (ADR-013
documenta o procedimento pra aplicar em cada um quando chegar a vez, incluindo a pré-checagem
de PR aberto/branch protection que pode tornar o rename não-trivial).

## D-2026-09-08-2: varredura de todos os repos + rename onde seguro, escalado onde não
Contexto: usuário pediu "atualizar todos que ainda estão desatualizados" (continuação de D-2026-09-08-1).
Varredura real em todo `~/projects/` (13 diretórios, checado owner/remote/branch/PR/workflow de cada um):
- **Achado**: `artists-booking`, `microgrow`, `rastafinancas`, `vetcare`, `agents-harness` já
  estavam em `main` — a suposição em ADR-013 (v1) de que ainda estariam em `master` estava errada,
  corrigida no próprio ADR com a tabela real da varredura.
- **Renomeado agora**: `dev-environment` (rastaFul, privado, sem PR, sem workflow referenciando
  `master`, sem `.specs` próprio) — mesmo procedimento de D-2026-09-08-1, verificado via
  `git branch -a` + `gh repo view --json defaultBranchRef`.
- **Escalado, não executado**: `developerFolio` (fork público ativo, `gh-pages` + branches de
  feature, 2 workflows referenciam `master` por nome, faz deploy real de site público — rename
  aqui não é só metadado, precisa editar workflow junto, risco maior que os outros); `tldr-projects`
  (anomalia: já existe `main` local órfã de 1 commit não relacionada + ref remota órfã sem remote
  configurado, working tree com mudanças não commitadas de outra frente — descartar a branch órfã
  não é decisão do agente).
- **Fora de escopo, não tocado**: `url-shortener` (owner `thiagomr`, não `rastaFul` — convenção
  deste workspace não se estende a repo de outro dono sem confirmação explícita).
Ver tabela completa em ADR-013 e `.specs/audit/execution.md`.

## D-2026-09-09-1: rastafinancas observability compose (telegraf/promtail down) + vetcare /metrics
Contexto: usuário reportou "composer de observabilidade não funcionando" + pediu correção do
`/metrics` do vetcare. Investigação real (não suposição) achou 2 problemas independentes:
1. `rasta-telegraf`/`rasta-promtail` estavam `Exited (255)` há ~26h por um `docker stop`
   explícito (log: `SIGINT/SIGTERM === exiting`, não crash/OOM/rede) — nunca voltaram porque
   `restart: unless-stopped` só resscita contêiner que estava `Up` no momento de um restart do
   daemon Docker, não um que já tinha sido parado antes. `docker compose up -d` resolveu,
   verificado com dado real chegando no InfluxDB e Loki (timestamps atuais, não antigos).
2. vetcare nunca teve `/metrics` implementado (spec `APPROVED` desde 08-28, nunca executada).
Decisão/execução: implementado em `vetcare` (repo próprio, ver DECISIONS.md de lá) + job
`vetcare` dedicado em `platform/prometheus/prometheus.yml` (não deu pra reusar `apis-host`
porque `metrics_path` é por job, e vetcare usa `/api/metrics` em vez de `/metrics`).
**Achado extra no caminho**: `docker compose restart prometheus` falhou com erro de bind-mount
órfão (bug conhecido Docker Desktop/WSL2 após edição de arquivo single-file bind-mounted fora do
Docker) — resolvido com `--force-recreate`. Sem isso, o `prometheus.yml` novo teria ficado sem
efeito silenciosamente; só foi pego porque verificação externa (`/-/healthy` + `/api/v1/targets`)
é obrigatória antes de considerar a task DONE.
Verificado: 6/6 targets Prometheus `up`, `vetcare_process_cpu_seconds_total` com dado real via
`GET /api/v1/query`. Gap conhecido, não escondido: vetcare ainda não expõe `http_requests_total`
(métricas HTTP por rota), então não aparece no dashboard "Golden Signals" ainda (variável
`$service` depende dessa métrica especificamente).
Pendência registrada, não resolvida: nenhum boot script resscita contêiner que já estava
`Exited` antes de um restart do Docker Desktop/WSL2 — pode se repetir com qualquer sidecar
telegraf/promtail do ecossistema. Precisa decisão do usuário sobre `wsl-boot.sh` explícito por
compose vs. aceitar o risco residual. Ver `.specs/audit/execution.md` sessão 2026-09-09.

## D-2026-09-09-2: restart:always em vez de script de boot (pendência 1 resolvida)
Contexto: usuário esclareceu a causa real do D-2026-09-09-1 — ele mesmo para o Docker Desktop pra
jogar, localmente, e espera que tudo volte sozinho ao reiniciar. Pediu resolver via config do
compose, não script.
Decisão: `restart: unless-stopped` → `restart: always` em TODOS os 7 composes reais do ecossistema
(platform, tunnel, rastafinancas x2, microgrow, artists-booking, vetcare) — `always` resscita no
restart do daemon Docker independente do estado do contêiner antes do shutdown (unless-stopped só
resscita o que estava `Up`), cobrindo tanto "parei o Docker de propósito" quanto "um sidecar crashou
sozinho antes de eu parar o Docker" (os 2 cenários reais já vistos neste projeto).
Aplicado ao vivo via `docker compose up -d` em cada um (recria só o que mudou, sem rebuild). 31
contêineres confirmados `Up`/saudáveis, 4/4 domínios públicos sem 502 (tunnel sobreviveu), Prometheus
6/6 targets `up`. `wsl-boot.sh` e o comentário de cabeçalho de cada compose atualizados (citavam
`unless-stopped` explicitamente).
2 achados colaterais registrados, não corrigidos (fora do pedido, precisam decisão própria): (1)
`rastafinancas_net` declarada não-external em 2 composes diferentes (frágil, funcionou por sorte de
nome); (2) `rastafinancas-api` usa nome de métrica HTTP divergente do resto do ecossistema
(`rasta_http_requests_total` vs `http_requests_total` esperado pelo dashboard Golden Signals) —
seus painéis de request-rate/error-rate/latência nunca mostraram dado real, ao contrário do que
STATE.md de 2026-08-28 registra. Ver `.specs/audit/execution.md` sessão 2026-09-09 pro detalhe.

## D-2026-09-09-3: as 3 pendências resolvidas (rename métrica, rede duplicada, instrumentação HTTP vetcare)
Contexto: usuário pediu "pode resolver as 3 pendências" (as 2 acima + a instrumentação HTTP do
vetcare que eu tinha deliberadamente não implementado na sessão anterior).
Decisão/execução:
1. **rastafinancas sem prefixo `rasta_`** em `collectDefaultMetrics` e em
   `http_requests_total`/`http_request_duration_ms` (era `_seconds`) — alinhado com
   artists-api/microgrow-api, compatível com o Golden Signals. Métricas de produto continuam
   prefixadas (`product-metrics.ts`, de propósito). Efeito colateral corrigido: dashboard
   `rasta-api-performance.json` (InfluxDB) + `alerting/rastafinancas.yaml` atualizados pros novos
   nomes — no processo, achado e corrigido um bug PRÉ-EXISTENTE e SEPARADO nos painéis P50/P95/P99
   (measurement/field errados desde a criação do dashboard, nunca retornaram dado; nova query Flux
   testada com dado real antes de ir pro JSON).
2. **`rastafinancas_net`**: observability compose passou a referenciar `external: true` (dono real
   é o compose principal do app) — warning de "rede pertence a projeto diferente" eliminado.
3. **vetcare instrumentação HTTP real**: `src/lib/with-metrics.ts` (wrapper que só funciona dentro
   do route handler, não do middleware — motivo já registrado em D anterior) aplicado nos 72
   handlers HTTP de 48 `route.ts` via codemod (`scripts/wrap-routes-with-metrics.mjs`, AST do
   TypeScript compiler API, reescrita por texto preservando formatação). `vetcare_` removido de
   `collectDefaultMetrics` pelo mesmo motivo do rastafinancas.
Verificação externa: gates completos nos 2 repos (tsc/vitest/jest/eslint/build real/rebuild de
container), Prometheus confirma os 4 produtos (`artists-api`/`microgrow-api`/`rastafinancas-api`/
`vetcare`) agora consistentes em `http_requests_total`/`process_resident_memory_bytes`, Grafana
recarregado com dashboard v4 + 6 alert rules de rastafinancas confirmadas via API (achado à parte:
`admin` autentica em `orgId=2` por padrão nesse Grafana multi-org — precisa header
`X-Grafana-Org-Id: 1` explícito pra bater com o que está provisionado). 4/4 domínios públicos sem
502 depois de tudo. Ver `.specs/audit/execution.md` sessão 2026-09-09 pro detalhe completo,
incluindo o achado novo não corrigido (lógica de `mean()` sobre contador cumulativo no alerta de
latência é aproximada, pré-existente, fora do pedido desta rodada).

## D-2026-09-09-4: `rasta-latency-p95` corrigido pra p95 real (bucket-based)
Usuário pediu pra atacar o achado registrado em D-2026-09-09-3. Query trocada de `mean()` sobre o
field `sum` (cumulativo, não é latência média real) pra quantil calculado a partir dos buckets do
histograma — mesma técnica já testada no dashboard `rasta-api-performance.json`.
Bug real cometido e corrigido na hora: comentário `#` (não é sintaxe Flux, que usa `//`) dentro da
query embutida no YAML quebrou a avaliação real do alerta (`health: error`) — só detectado
verificando a avaliação de verdade via API do Grafana, não pela validação de sintaxe do YAML em
si (que não valida o conteúdo da string de query Flux). Corrigido, reconfirmado saudável (`health:
ok`, valor real `5ms`) em 2 ciclos de avaliação consecutivos.
Lição registrada: query embutida como string numa linguagem diferente do arquivo host precisa de
verificação da AVALIAÇÃO REAL depois de qualquer edição no artefato final, não só do fragmento
testado isoladamente antes.

## D-2026-09-09-5: SMTP dos alertas fica no Resend (não Gmail) — não é prioridade agora
Usuário decidiu manter tudo centralizado no Resend (já usado pelo rastafinancas, mesmo domínio
verificado `rastaful.dev`) em vez de configurar app password do Gmail pro SMTP do Grafana.
Explicitamente marcado como NÃO prioridade agora — não vou configurar isso nesta rodada, fica
registrado pra quando o usuário pedir. Quando for feito: trocar `GF_SMTP_HOST`/`GF_SMTP_FROM_ADDRESS`
em `platform/docker-compose.yml`/`.env` pro relay SMTP do Resend (`smtp.resend.com`) + adicionar
`GF_SMTP_USER`/`GF_SMTP_PASSWORD` (API key do Resend) — hoje não existe nenhum dos dois, nem pro
Gmail nem pro Resend, é por isso que a notificação nunca funcionou.
