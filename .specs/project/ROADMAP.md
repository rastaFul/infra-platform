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
- [ ] Módulo Terraform `oci-compute/` (VCN, subnet, security list, instância ARM, cloud-init com Coolify)
- [ ] `environments/oci-free/`
- [ ] Deploy da platform stack via Coolify no Oracle
- [ ] Migração PM2 → Docker Compose (1 serviço por vez)
- Ver ADR 005, 007, 008 | Spec: `docs/how-to/provision-oracle-free-tier.md` (DRAFT)

## Batch 2 — CI/CD por projeto — NOT STARTED

- [ ] Per-project `docker-compose.yml` com redes isoladas
- [ ] GitHub Actions CI (reusable workflow, 5 repos) — lint, test, `tsc`, `docker build`
- [ ] Coolify CD (só em merge `main`, só quando `oci-free` existir)
- [ ] Grafana dashboards golden signals (artists/rasta/vetcare — microgrow já tem)
- Ver ADR 006, 009

## Batch 3 — Vault real + migração completa — NOT STARTED

- [ ] `vault-init.sh` (unseal, AppRole por projeto) — ver D-2026-08-27-4
- [ ] Migração de segredos `.env` → Vault dynamic secrets
- [ ] Promtail: logs PM2 → Docker socket

## Segurança Profissional — Fase 1 — DONE (2026-08-28)

- [x] `features/security-hardening-phase1/spec.md` — JWT fail-fast, CORS exact-match, `/metrics` token auth, CI gates (npm audit + trivy), Vault init + AppRole por projeto — todas as 5 tasks executadas, 6 bugs reais achados e corrigidos no processo (vault-init.sh x2, reusable CI workflow x3, colisão de sessão paralela x1)
- [ ] `features/security-audit-auth-session/spec.md` — auditoria de sessão/senha/cookie por produto (ainda não iniciada)
- [ ] `features/backup-strategy/spec.md` — backup de SQLite/Postgres/InfluxDB (pain point aberto desde a spec original de 12/08, nunca resolvido)
- [ ] Débito de código achado pelo CI novo (fora do escopo de infra, backlog do produto): CVE crítico `tar@7.5.11` + erros `tsc` em artists-booking

## Ambiente de Desenvolvimento — Fase 1 DONE (repo criado, dry-run validado)

- [x] Decidido: Ansible (não Vagrant) — sem repo legado a respeitar
- [x] Repo `dev-environment` criado (privado) — `github.com/rastaFul/dev-environment`
- [x] 4 roles escritas: `credentials-check`, `packages`, `dotfiles`, `agents-harness`
- [x] Gates: `--syntax-check` PASS, `--check --diff` dry-run PASS (0 failed)
- [ ] Rodar de verdade nesta máquina (não `--check`) — fecha o drift achado em `~/.claude/skills`/`steering`
- [ ] `ansible-lint` — pendente máquina com Python 3.9+
- [ ] Validar `darwin.yml` no primeiro Mac real
- Ver D-2026-08-27-21

## Fase 2+ — AWS (`aws-prod`) — NOT STARTED

Só quando houver receita/escala que justifique. Mesmas imagens, mesmo pipeline — troca de destino, não reescrita.

---

**Legenda:** DONE / NOT STARTED / IN_PROGRESS / BLOCKED. Atualizar a cada transição real (ver `STATE.md` para o detalhe sessão-a-sessão).
