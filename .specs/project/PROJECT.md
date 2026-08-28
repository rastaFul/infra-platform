# PROJECT — rastaFul Infra Platform

(Conteúdo anterior deste arquivo era de outro projeto — "Clock of Clocks" — parado aqui por acidente de diretório de sessão. Corrigido 2026-08-27, ver `docs/reference/repository-layout.md`.)

## Vision

Infraestrutura compartilhada, segura e portável entre clouds para os produtos pessoais do rastaFul (artists-booking, microgrow, rastafinancas, vetcare). Sair de "10 processos PM2 numa máquina WSL2 sem CI/CD" para uma base profissional — sem gastar antes de precisar, com portabilidade real de cloud como requisito de primeira classe (custo + aprendizado).

## Objetivos

1. **IaC de verdade** — tudo que é infra é código versionado, gates externos validam antes de confiar (Terraform, Docker, Ansible)
2. **Observabilidade unificada** — uma stack só (Vault, OTEL, Prometheus, Grafana, Loki, InfluxDB, GlitchTip), sem duplicação
3. **CI/CD separados** — GitHub Actions (CI, sempre) + Coolify (CD, só quando há destino real)
4. **Portabilidade de cloud** — Oracle Free Tier primeiro (custo zero, valida o pipeline), AWS depois (quando houver receita), imagens Docker agnósticas de cloud
5. **Segurança profissional** — segredos via Vault (não `.env` estático), gates de vulnerabilidade automatizados, comunicação entre camadas auditada e documentada
6. **Ambiente de dev reprodutível** — bootstrap idempotente (Ansible) entre WSL2, Linux nativo e Mac

## Produtos servidos

| Produto | Tipo | Runtime atual |
|---|---|---|
| artists-booking | Fastify API + Next.js web | PM2 |
| microgrow | Fastify API + Next.js web + simulador Python | PM2 |
| rastafinancas | Fastify API + Next.js web | PM2 |
| vetcare | Next.js monolito (API routes internas) | PM2 |

## Stack

- **Compute (hoje):** WSL2 + PM2 (transição pra Docker Compose em andamento)
- **Compute (Fase 1):** Oracle Cloud Always Free (ARM) + Coolify
- **Compute (Fase 2+):** AWS ECS Fargate
- **IaC:** Terraform (state no Terraform Cloud, cloud-agnóstico)
- **Config management:** Ansible (dev machine bootstrap + provisionamento de VM)
- **Observabilidade:** Vault, OTEL Collector, Prometheus, Grafana, Loki, InfluxDB, GlitchTip — uma stack só em `infra-platform/platform/`
- **Ingress:** Cloudflare Tunnel (padrão BFF-proxy — só frontend público)
- **CI:** GitHub Actions (reusable workflow)
- **CD:** Coolify

## Repos

- `infra-platform` (este) — fonte de verdade de infra
- `agents-harness` — config dos agentes de IA (Claude Code)
- `artists-booking`, `microgrow`, `rasfaful-finances`, `vetcare` — produtos
- `dev-environment` (planejado) — bootstrap Ansible multi-SO

Ver `ROADMAP.md` para o estado atual de cada frente.
