# ROADMAP — rastaFul Infra Platform

Primeira versão deste arquivo — nunca existiu antes (só `STATE.md`/`DECISIONS.md` rastreavam progresso). Consolidado 2026-08-27.

## Fase 0 — Local Hardening — DONE

- [x] `infra-platform` repo criado, versionado, pushed
- [x] Dockerfiles multi-stage (8 serviços) + gate `docker build` fechado (8/8 PASS, 5 bugs reais corrigidos)
- [x] `/health` + `/metrics` + GlitchTip + OTEL SDK nos 3 APIs Fastify
- [x] Platform stack consolidada (Vault, OTEL, Prometheus, Grafana, Loki, InfluxDB, GlitchTip — um compose só, ADR 010)
- [x] Tunnel migrado + padrão BFF-proxy documentado (ADR 011)
- [x] Organização de repos/`.specs` corrigida (ADR 012)

## Fase 1 — Oracle Free Tier (`oci-free`) — NOT STARTED

- [ ] Conta Oracle Cloud (usuário) + API key
- [ ] Conta Terraform Cloud (usuário) + token
- [x] Módulo Terraform `oci-compute/` (VCN, subnet, security list — só SSH, sem porta de app — instância ARM, cloud-init com Docker+Coolify) — escrito 2026-08-28, `validate`/`fmt`/`init` PASS, `plan` real bloqueado até as contas existirem (teto do testável agora)
- [x] `environments/oci-free/` (backend Terraform Cloud, ADR 008)
- [ ] Deploy da platform stack via Coolify no Oracle
- [x] Migração PM2 → Docker Compose (1 serviço por vez) — feito 2026-08-29, ver Batch 3
- Ver ADR 005, 007, 008 | Spec: `docs/how-to/provision-oracle-free-tier.md` (DRAFT)

## Batch 2 — CI/CD por projeto — quase tudo DONE

- [x] Per-project `docker-compose.yml` com redes isoladas — **já estava adequado**, verificado 2026-08-28: `artists_net` explícita, `microgrow` tem a sua, rastafinancas não precisa (SQLite, sem serviço extra), vetcare usa rede default do Compose (isolada na prática, só não segue a convenção de nome explícito `<project>_net` — achado LOW, cosmético)
- [x] GitHub Actions CI (reusable workflow, 4 repos) — feito 2026-08-28 (`security-hardening-phase1`, Task 3)
- [ ] Coolify CD (só em merge `main`, só quando `oci-free` existir) — bloqueado até Oracle
- [x] Grafana dashboards golden signals — **achado 2026-08-28**: `golden-signals.json` (criado no Batch 1, órfão até o Prometheus existir) já cobre artists-booking e rastafinancas via variável `$service`, confirmado com dado real fluindo. microgrow já tinha os próprios. **vetcare é o único sem `/metrics`** — spec delegada pro harness-dev (`vetcare/.specs/features/observability-metrics/spec.md`)
- Ver ADR 006, 009

## Batch 3 — Vault real + migração completa — quase tudo DONE

- [x] `vault-init.sh` (unseal, AppRole por projeto) — feito 2026-08-27, ver D-2026-08-27-4/D-2026-08-28-3
- [x] Migração de segredos `.env` → Vault (KV v2) — feito 2026-08-28. Não é "dynamic secrets" de verdade (short-lived), é Vault-como-fonte-canônica + sync pro `.env` — decisão deliberada pra essa escala. Ver `docs/how-to/vault-secrets-workflow.md` e D-2026-08-28-7
- [x] Migração PM2 → Docker Compose completa — 5/5 componentes (rastafinancas, microgrow, vetcare, artists-booking, platform-tunnel), feito 2026-08-29. Incidente real no meio (tunnel remotely-managed apontando pro `localhost` pré-containerização, 6 rotas públicas em 502) achado e corrigido, validado com curl real. Ver `features/local-boot-persistence/spec.md` (DONE), D-2026-08-28-10
- [ ] **Promtail: logs PM2 → Docker socket** — agora literalmente quebrado (não só pendente): Promtail ainda lê `~/.pm2/logs`, que não recebe mais nada desde que os 5 componentes migraram pra Docker. Nenhum log de app está indo pro Loki agora. Próximo passo natural — ver abaixo.

## Segurança Profissional — Fase 1 — DONE (2026-08-28)

- [x] `features/security-hardening-phase1/spec.md` — JWT fail-fast, CORS exact-match, `/metrics` token auth, CI gates (npm audit + trivy), Vault init + AppRole por projeto — todas as 5 tasks executadas, 6 bugs reais achados e corrigidos no processo (vault-init.sh x2, reusable CI workflow x3, colisão de sessão paralela x1)
- [x] `features/security-audit-auth-session/spec.md` — investigação concluída. rastafinancas: maduro (rate limit por rota, secure condicional, bcrypt 12). artists-booking: 2 gaps (sem rate limit em auth — HIGH; cookie sem `secure` — MEDIUM; bcrypt 10 — LOW). microgrow/vetcare: sem superfície de auth custom relevante.
- [x] Achados delegados pro `harness-dev`: spec `artists-booking/.specs/features/21-security-hardening/spec.md` (APPROVED, pronta pra execução com TDD quando o usuário pedir) — ver D-2026-08-28-5
- [x] `features/backup-strategy/spec.md` — backup local ativo e testado (SQLite, Postgres, 4 volumes Docker, Vault keys — 89MB, restore validado de verdade). Pain point aberto desde 12/08, **resolvido**. R2 (redundância remota) pronto no código, desativado de propósito (usuário não quer gastar ainda). Cron configurado, daemon precisa `sudo service cron start` (usuário)
- [ ] Débito de código achado pelo CI novo (fora do escopo de infra, backlog do produto): CVE crítico `tar@7.5.11` + erros `tsc` em artists-booking

## Ambiente de Desenvolvimento — Fase 1 DONE (repo criado, dry-run validado)

- [x] Decidido: Ansible (não Vagrant) — sem repo legado a respeitar
- [x] Repo `dev-environment` criado (privado) — `github.com/rastaFul/dev-environment`
- [x] 4 roles escritas: `credentials-check`, `packages`, `dotfiles`, `agents-harness`
- [x] Gates: `--syntax-check` PASS, `--check --diff` dry-run PASS (0 failed)
- [x] Rodar de verdade nesta máquina (não `--check`) — feito 2026-08-28, 2 bugs reais achados/corrigidos (templates `ansible_managed` sem `#`, bug do módulo `git` no ansible-core 2.13.13), drift de `~/.claude/skills`/`steering` fechado. Ver D-2026-08-28-1
- [ ] `ansible-lint` — pendente máquina com Python 3.9+
- [ ] Validar `darwin.yml` no primeiro Mac real
- Ver D-2026-08-27-21

## Fase 2+ — AWS (`aws-prod`) — NOT STARTED

Só quando houver receita/escala que justifique. Mesmas imagens, mesmo pipeline — troca de destino, não reescrita.

---

**Legenda:** DONE / NOT STARTED / IN_PROGRESS / BLOCKED. Atualizar a cada transição real (ver `STATE.md` para o detalhe sessão-a-sessão).
