# ADR 010 — Platform Stack Consolidation (single docker-compose.yml)

**Status:** ACCEPTED
**Date:** 2026-08-27
**Deciders:** rodrigob.dev@gmail.com

---

## Context

User audit ("por que tem `services` e `infra-platform`?") surfaced real duplication I had let slide: two separate "shared platform" stacks existed simultaneously —

- `~/projects/services/platform/` (created 06/2026, per the original `infra-reorg` spec): Grafana, InfluxDB, Loki, GlitchTip. Not running at audit time, but was the stack the live Cloudflare Tunnel (`metrics.rastaful.dev`) and all Grafana dashboards actually pointed at.
- `~/projects/infra-platform/platform/` (created 08/2026, Batch 1): Vault, OTEL Collector. Running, but new and disconnected from the older stack.

Digging further found **three generations of orphaned Docker volumes** for the same logical data (`infra_*`, `observability_*`, `platform_*`) — evidence this had already happened before, silently, from directory renames over the project's history (Compose derives volume names from the directory basename by default; renaming the directory orphans the old volume).

## Decision

One `docker-compose.yml`, one directory: `infra-platform/platform/`. All services — Vault, OTEL Collector, Prometheus (new, ADR 009), InfluxDB, Grafana, Loki, GlitchTip (db+redis+web+worker) — live there.

**Volumes are pinned via explicit `name:`**, permanently, to the exact names already holding real data (`platform_influx_data`, `platform_grafana_data`, `platform_loki_data`, `platform_glitchtip_postgres_data`, `platform_glitchtip_uploads`, `platform_vault_data`, `platform_vault_logs`, new: `platform_prometheus_data`). This is the actual fix for the volume-orphaning root cause — the directory can be renamed again in the future and data won't move, because the name is no longer implicit.

Migration executed 2026-08-27: containers from the old stack stopped (`docker compose down`, no `-v` — volumes preserved), config files (`grafana/provisioning`, `loki/loki-config.yaml`, `dashboards/`, `.env`) moved into the new location, merged compose file written, brought up against the same volume names. Verified zero data loss: Grafana `database: ok`, GlitchTip `_health/: ok`, Prometheus scraping successfully post-migration.

**Bonus fix found by actually running the merged stack:** `otel-collector`'s Docker `HEALTHCHECK` used `wget`, but `otel/opentelemetry-collector-contrib` is a distroless image — no shell, no wget, nothing to exec (`docker exec ... wget` → exit 127). It had been silently reporting `unhealthy` the entire time despite the endpoint working fine. Healthcheck removed; liveness is now covered by Prometheus's own scrape-target health instead (`up{job="otel-collector"}`), which is a more accurate signal anyway.

`golden-signals.json` (created Batch 1, orphaned in `observability/dashboards/`, never actually provisioned into Grafana) moved into `platform/dashboards/platform/` — now actually loads.

## Consequences

**Positive:**
- One place to look for "what's the shared platform stack" — matches `repository-layout.md`'s own rule that it claims to enforce but this violated for 2+ months.
- Volume-orphaning root cause fixed permanently (pinned names), not just patched this once.
- Real historical data (142MB InfluxDB, 155MB GlitchTip issues) preserved and verified, not silently lost.

**Negative:**
- None identified — this was pure debt removal.

## References
- ADR 007 (Oracle Free Tier) — this consolidated stack is what deploys there
- ADR 009 (Prometheus added)
- `docs/reference/repository-layout.md` — updated to reflect this
