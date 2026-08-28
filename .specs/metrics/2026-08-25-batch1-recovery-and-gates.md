# Metrics — Batch 1 Recovery + Gate Closure

**Date:** 2026-08-25
**Scope:** infra-strategy Phase 0, Batch 1

## Incident Recovery
- Downtime detected: 10/10 PM2 processes down (unknown duration, discovered on session resume)
- Recovery time: ~1 min (pm2 resurrect)
- Secondary incident: artists-api crash loop (178 restarts), root cause MODULE_NOT_FOUND prom-client
- Fix time: ~5 min (dependency install workaround + verification)

## Gates Run (previously skipped, now closed)
| Gate | artists-api | microgrow-api | rastafinancas-api |
|------|-------------|----------------|--------------------|
| tsc --noEmit | FAIL→FIXED→PASS | FAIL→FIXED→PASS | PASS |
| /health (curl) | PASS (200) | PASS (200) | PASS (200) |
| /metrics (curl) | PASS (200) | PASS (200) | PASS (200) |
| docker compose YAML syntax | PASS | PASS | PASS |
| docker build | BLOCKED (Docker Desktop offline) | BLOCKED | BLOCKED |

## Bugs Found (introduced 2026-08-12, never gated before this session)
1. artists-api: `prom-client` declared but not installed → crash loop
2. artists-api + microgrow-api: `Sentry.autoDiscoverNodePerformanceMonitoringIntegrations` — removed API in @sentry/node v10
3. artists-api: unreachable 'degraded' health branch (TS2367)

## Environment Issues (not code)
- pnpm 7.1.7 in artists-booking incompatible with current npm registry (ERR_INVALID_THIS) — workaround applied, root fix deferred (needs own spec, affects monorepo lockfile)
- Docker Desktop (Windows host) not running/mounted in WSL2 — blocks all docker-dependent gates, needs manual user action

## Files Changed
- `/home/rodrigo/projects/artists-booking/apps/api/src/interface/http/plugins/observability.plugin.ts`
- `/home/rodrigo/projects/microgrow/api/src/plugins/glitchtip.ts`
- (node_modules) prom-client installed for artists-booking apps/api

## Status: Batch 1 DONE (docker build gate pending Docker Desktop restart)
