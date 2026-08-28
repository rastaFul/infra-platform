# SPEC: Infra Strategy — Local → Cloud Migration

## Status: RESEARCH
## Created: 2026-08-12
## Owner: rodrigo (senior DevOps)

---

## Context

WSL2 machine running 10 PM2 processes + Docker Compose platform stack.
All exposed via Cloudflare Tunnel → rastaful.dev.
Zero CI/CD. No containerized apps. No secret management.
Goal: design a robust, incremental path to cloud — keeping it simple and secure from day 0.

---

## Projects Inventory

| App | Type | Port | DB | Runtime |
|-----|------|------|----|---------|
| rastafinancas-api | Fastify API | 3001 | SQLite (LibSQL/Drizzle) | tsx (dev-mode in prod) |
| rastafinancas-web | Next.js | 3000 | — | npm start |
| microgrow-api | Fastify API | 4000 | — (MQTT/InfluxDB) | tsx |
| microgrow-webapp | Next.js | 3002 | — | static server |
| microgrow-webapp-sim | Next.js | 3003 | — | static server |
| microgrow-simulator | Python daemon | — | — | python3 |
| artists-api | Fastify API | 3006 | SQLite (Prisma) | tsx |
| artists-web | Next.js | 3005 | — | npm start |
| vetcare | Next.js + API | 3004 | PostgreSQL (Prisma) | npm start |
| platform-tunnel | Cloudflare tunnel | — | — | cloudflared |

## Platform Services (Docker Compose)

| Service | Image | Port | Notes |
|---------|-------|------|-------|
| platform-grafana | grafana:10.4.0 | 3010 | metrics.rastaful.dev |
| platform-influxdb | influxdb:2.7 | 8086 | time-series (microgrow) |
| platform-loki | loki:2.9.10 | 3100 | log aggregation |
| microgrow-promtail | promtail:2.9.0 | — | log shipper |
| microgrow-telegraf | telegraf:1.30 | — | metrics collector |
| microgrow-mosquitto | eclipse-mosquitto:2 | 1883/9001 | MQTT broker |
| platform-glitchtip | glitchtip/glitchtip | 8010 | error tracking |
| vetcare-postgres | postgres:16-alpine | 5432 | vetcare prod DB |
| vetcare-postgres_test | postgres:16-alpine | 5433 | vetcare test DB |
| artists-mailhog | mailhog/mailhog | 1025/8025 | mail dev/test |

## Network

- Host: WSL2 / Linux 6.18 (Windows machine)
- Egress: Cloudflare Tunnel (single tunnel ID: 4b4b58f0)
- DNS: *.rastaful.dev → Cloudflare → tunnel → localhost
- All services: localhost bind only (secure)

---

## Pain Points Identified

### Critical
1. **No CI/CD** — zero automation. Deploy = git pull + pm2 restart manually.
2. **tsx in production** — all APIs run `npx tsx src/app.ts`. No build step. Dev tooling in prod.
3. **artists-api: 567 restarts** — chronic crash loop. Needs investigation.
4. **No secret management** — .env files on disk, secrets injected directly into PM2 ecosystem env.
5. **No rollback** — no versioning, no artifact, no blue/green.

### High
6. **Mixed DB strategy** — SQLite (rastafinancas, artists), PostgreSQL (vetcare). Inconsistent.
7. **No health checks** — PM2 has no HTTP health check config.
8. **No log rotation** — PM2 logs grow unbounded.
9. **Single Cloudflare tunnel** — SPOF for all public traffic.
10. **No staging environment** — prod is dev machine.

### Medium
11. **Inconsistent observability** — only rastafinancas uses @sentry/node. Others have no error tracking wired.
12. **No resource limits** — only max_memory_restart. No CPU limits.
13. **WSL2 fragility** — Windows update can kill everything. No persistence guarantee.
14. **No backup strategy** — SQLite DBs not backed up. InfluxDB/Postgres volumes not snapshotted.

---

## Research Questions (to answer before architecting)

1. What's the target cloud? (AWS given vetcare uses @aws-sdk, but confirm)
2. What's the migration timeline? Weeks? Months?
3. Which projects are "production" (real users) vs internal/dev?
4. Budget constraints for cloud?
5. Preferred container orchestration? (ECS, EKS, Fly.io, Railway, Render?)
6. Monorepo or poly-repo? (currently poly-repo across GitHub/rastaFul org)

---

## Proposed Architecture Tracks (to discuss)

### Track A: Local Hardening (immediate, no cloud)
- Docker Compose for apps (not just platform)
- GitHub Actions: lint + test + build on push
- Secrets: Doppler or .env.vault locally
- Nginx/Caddy reverse proxy locally
- PM2 → keep but with proper ecosystem (cluster mode, health checks, log rotate)

### Track B: Partial Cloud (1-3 months)
- DBs migrate first: Turso (rastafinancas), Railway Postgres (artists, vetcare)
- Apps still local but CI pipeline builds Docker images → push to GHCR
- Deployment: pull image on local → docker compose up
- Secrets: GitHub Actions secrets → inject at build/deploy time

### Track C: Full Cloud (3-6 months)
- Apps containerized → ECS Fargate or Fly.io (simple) or EKS (complex)
- Platform services: managed (RDS, CloudWatch, AWS managed Grafana)
- CI/CD: GitHub Actions → GHCR → deploy via SSH or ECS deploy action
- Cloudflare: keep as CDN + WAF (not tunnel)

---

## Decisions Needed (from architect)

- [ ] D1: Cloud target (AWS / Fly.io / Railway / hybrid)
- [ ] D2: Container strategy for apps (Docker Compose → ECS or K8s)
- [ ] D3: DB consolidation (all PostgreSQL? keep SQLite for simple apps?)
- [ ] D4: CI/CD tool (GitHub Actions — already on GH)
- [ ] D5: Secret management (Doppler / Vault / GitHub Secrets / AWS SSM)
- [ ] D6: Reverse proxy local (Caddy vs Nginx vs Traefik)
- [ ] D7: Staging environment strategy (local Docker network? cloud staging?)
- [ ] D8: Monorepo or keep poly-repo?

---

## Next Steps (after architect decisions)

1. Fix critical: build step for APIs (tsc compile, not tsx in prod)
2. Add GitHub Actions: CI pipeline per repo
3. Containerize apps: Dockerfile per service
4. Secret management baseline
5. Local reverse proxy replacing tunnel for non-public services
6. Staging environment definition
