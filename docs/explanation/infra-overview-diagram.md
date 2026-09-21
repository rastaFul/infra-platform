# Minha Infra — Visão Geral

## 1. Provisionamento: mesmo Terraform, qualquer cloud

```
                    ┌─────────────────────────────┐
                    │   Terraform Cloud (free)     │
                    │   state remoto + lock         │
                    │   1 workspace por ambiente    │
                    └──────────────┬────────────────┘
                                   │
        terraform/modules/  (reescreve nada, troca alvo)
   ┌─────────┬─────────┬──────────┼──────────┬──────────┬─────────┐
   │ vpc     │  ecs-   │  oci-    │  k8s-    │  rds-    │ cloudflare-
   │         │ service │ compute  │ service  │ postgres │   dns
   └─────────┴─────────┴──────────┴──────────┴──────────┴─────────┘
                                   │
        terraform/environments/  (1 dir/tfvars por ambiente)
   ┌────────────────────┬────────────────────┬─────────────────────┐
   │  local (WSL2)       │  oci-free (Oracle)  │  aws-prod (futuro)   │
   │  Compose direto      │  Coolify            │  ECS Fargate/Coolify  │
   │  $0                  │  $0                 │  pago                 │
   └────────────────────┴────────────────────┴─────────────────────┘
```

**Trocar de cloud = trocar `environments/<nome>` + módulo Terraform correspondente.**
Nenhum código de app muda, nenhum Dockerfile muda, nenhum passo manual.

## 2. Ingress universal: Cloudflare na frente de qualquer origem

```
   Client
     │
     ▼
 Cloudflare (DNS + TLS + WAF)  ← único ponto que muda numa troca de cloud
     │
     ▼
 Origin atual: Cloudflare Tunnel → VM oci-free
 Origin futura: ALB (AWS) / Cloud LB (GCP) / Fly.io Anycast
     │
     ▼
 Container (MESMA imagem Docker, qualquer cloud)
```

Migrar de cloud = subir containers no novo destino, trocar a origin no Cloudflare, monitorar, desligar o antigo. Downtime = TTL do DNS (60s).

## 3. Padrão BFF-proxy: só o frontend é público

```
 Browser → https://<projeto>.rastaful.dev/api/*   (1 hostname público)
                │
                └─ next.config.js (rewrite server-side)
                       │
                       └─ http://localhost:<porta-api>/api/*  (NUNCA público)
```

API não tem hostname próprio no túnel — sem CORS a endurecer, sem WAF duplicado.
Exceção só se não houver frontend na frente (ex.: webhook receiver).

## 4. Stack compartilhada — 1 definição, todos os projetos consomem

```
infra-platform/platform/docker-compose.yml   ← ÚNICA definição, roda em local E oci-free
┌────────────────────────────────────────────────────────────────┐
│  Vault  │ OTEL Collector │ Prometheus │ Grafana │ Loki          │
│  InfluxDB │ GlitchTip (+worker) │ Postgres/Redis do GlitchTip   │
└──────────────────────────────┬───────────────────────────────────┘
                                │  rede externa: platform_net
        ┌───────────┬──────────┼───────────┬───────────┐
        ▼           ▼          ▼           ▼           ▼
   artists-    microgrow  rastafinancas  vetcare    (novo projeto)
   booking
```

Cada projeto **entra** na `platform_net` (network externa) — nunca redefine Vault/Grafana/etc.
Só o que é específico do projeto (ex.: mosquitto do microgrow, evolution-api do vetcare) fica no `infra/` do próprio repo de app.

## 5. Resumo — por que isso escala sem reescrever nada

| Camada | Reescreve ao trocar de cloud? |
|---|---|
| Imagem Docker do app | Não |
| Terraform (módulos) | Não |
| `docker-compose.yml` da stack compartilhada | Não |
| Cloudflare (ingress) | Só a origin |
| CI (GitHub Actions) | Não |
| CD (Coolify) | Só o alvo de deploy |
| State (Terraform Cloud) | Não (já é cloud-agnostic) |

Fonte: `infra-platform/docs/explanation/adr/004,005,006,007,008,011` e `docs/reference/repository-layout.md`.
