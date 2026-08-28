# Spec: Infra Reorganization — Platform Layer Extraction

**Date:** 2026-06-03  
**Status:** APPROVED  
**Scope:** Local WSL2 environment (CloudFlare tunnel)

---

## Objective

Extract shared observability infrastructure into a dedicated `~/services/platform/` layer,
separate the CloudFlare tunnel from application repos, and fix security issues identified
in the current mixed setup.

No containers will be restarted automatically — the user controls when to apply changes.

---

## Done Criteria

1. `~/services/platform/` exists with working docker-compose (Grafana + InfluxDB + Loki + GlitchTip)
2. `~/services/tunnel/` exists with cloudflared config and pm2.config.js
3. `microgrow/infra/docker-compose.yml` no longer contains grafana, influxdb, or loki
4. `rastafinancas/infrastructure/docker-compose.yml` no longer contains rasta-loki or glitchtip
5. All containers connect via `platform_net` (external) for shared backends
6. `microgrow_net` and `rastafinancas_net` are isolated networks
7. `.env.example` exists for each compose stack with all required variables
8. Grafana anonymous access disabled
9. InfluxDB tokens separated per project (env vars)
10. Mosquitto WebSocket removed from CloudFlare tunnel routes
11. `rastafinancas-tunnel` removed from rastafinancas ecosystem.config.js
12. New `~/services/tunnel/pm2.config.js` created for tunnel process

---

## Architecture

```
~/services/
├── platform/              ← NEW: shared observability
│   ├── docker-compose.yml (grafana, influxdb, loki, glitchtip stack)
│   ├── .env.example
│   ├── .env               (gitignored, user fills in)
│   ├── grafana/provisioning/
│   ├── dashboards/{microgrow,rastafinancas}/
│   └── loki/loki-config.yaml
└── tunnel/                ← NEW: cloudflare tunnel (neutral ownership)
    ├── cloudflared/config.yml
    └── pm2.config.js

~/projects/microgrow/infra/
  docker-compose.yml       ← ONLY: mosquitto, microgrow-telegraf, microgrow-promtail
  networks: microgrow_net (bridge) + platform_net (external)

~/projects/rastafinancas/infrastructure/
  docker-compose.yml       ← ONLY: rasta-telegraf, rasta-promtail
  networks: rastafinancas_net (bridge) + platform_net (external)
```

---

## Tasks

| # | Task | Agent | Depends On |
|---|------|-------|------------|
| 1 | Create ~/services/platform/ | task-executor | — |
| 2 | Create ~/services/tunnel/ | task-executor | — |
| 3 | Refactor microgrow/infra/ | task-executor | Task 1 |
| 4 | Refactor rastafinancas/infrastructure/ | task-executor | Task 1 |
| 5 | Security hardening + pm2 cleanup | task-executor | Tasks 3,4 |

---

## Networks

- `platform_net` — owned by platform/docker-compose.yml
- `microgrow_net` — owned by microgrow/infra/docker-compose.yml
- `rastafinancas_net` — owned by rastafinancas/infrastructure/docker-compose.yml
- Projects join `platform_net` as `external: true`

---

## Secrets Strategy

Local: `.env` files (gitignored), `.env.example` versionado
Cloud-ready: todas as vars são injetadas; trocar URL é suficiente para migrar

---

## InfluxDB Token Strategy

Single admin token for init (backward compatible).
Env vars defined per-scope so they can be made distinct later:
- INFLUXDB_ADMIN_TOKEN → setup + init
- INFLUXDB_TOKEN_MICROGROW → telegraf microgrow write (sensors bucket)
- INFLUXDB_TOKEN_RASTAFINANCAS → telegraf rasta write (rastafinancas bucket)
- INFLUXDB_TOKEN_GRAFANA → grafana read-all

---

## Security Fixes Included

- Grafana: disable anonymous access, admin password via env var
- InfluxDB: password via env var, admin token via env var
- GlitchTip: SECRET_KEY via env var (≥50 chars), DSN uses container name
- Mosquitto: WebSocket removed from CloudFlare tunnel
- All sensitive values moved to .env (never hardcoded)
