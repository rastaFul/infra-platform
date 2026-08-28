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

## D-2026-08-27-4: vault-init.sh adiado para Batch 3
Contexto: com Docker Desktop de volta, `docker compose up` do platform stack (Vault + OTEL Collector) rodou limpo e `vault status` respondeu (uninitialized, sealed — esperado). O script `vault-init.sh` de fato inicializa o Vault, gerando root token + unseal keys (ação sensível, sem rollback trivial).
Decisão: não executar vault-init.sh como parte do fechamento de gate do Batch 1. Fica como primeira tarefa formal do Batch 3, com spec própria cobrindo AppRole por projeto. Containers vault/otel-collector deixados rodando (isolados, portas só 127.0.0.1) — não há motivo pra derrubar.
