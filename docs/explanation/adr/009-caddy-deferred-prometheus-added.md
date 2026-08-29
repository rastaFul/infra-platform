# ADR 009 — Caddy Deferred to Track C, Prometheus Added as Batch 2 Prerequisite

**Status:** ACCEPTED
**Date:** 2026-08-27
**Deciders:** rodrigob.dev@gmail.com

---

## Context

Two scoping questions came up while planning Batch 2 (per-project Compose, ingress, CI, dashboards).

### Caddy
Original Batch 2 scope included "Caddy config" as a local reverse proxy in front of app services, behind the Cloudflare Tunnel. Cloudflare Tunnel already handles TLS termination, WAF, and DDoS protection at the edge for free, and works today. A local Caddy layer would add rate-limiting/header control/compression and a portable ingress definition — but has no ingress this project currently lacks, and duplicates work the Tunnel already does.

### Prometheus
Investigating the Batch 1 output (`golden-signals.json` Grafana dashboard) surfaced a real gap: every API exposes `/metrics` (prom-client) and the OTEL Collector exposes a Prometheus-format endpoint (`:8889`), but **no Prometheus server exists anywhere in the stack** to scrape either. Grafana's only wired datasources are InfluxDB and Loki. The golden-signals dashboard, built against a `prometheus` datasource, would render "no data" if provisioned as-is.

## Decision

**Caddy: deferred to Track C** (real cloud ingress, ADR from `multi-cloud-strategy.md` Phase 2). Not part of Batch 2. Cloudflare Tunnel remains the sole ingress for `local` and `oci-free`. Revisit only if a concrete need appears (e.g. local rate-limiting, canary routing) that Cloudflare doesn't cover.

**Prometheus: added to the shared platform stack** (`infra-platform/platform/docker-compose.yml`), alongside Vault and OTEL Collector, self-hosted for now — same portability posture as everything else (swappable for AWS Managed Prometheus later without touching app code). Configured to scrape the OTEL Collector's `:8889/metrics` and each API's `/metrics` directly. This is a **prerequisite** for the Batch 2 Grafana dashboard work (artists/rasta/vetcare golden signals) — those dashboards are meaningless without a working Prometheus datasource behind them.

## Consequences

**Positive:**
- Avoids building an ingress layer with no current requirement.
- Closes a real, previously-undetected observability gap (dashboards that would have shipped broken).

**Negative:**
- Adds one more container (Prometheus) to the resource budget on the `oci-free` VM (ADR 007) — acceptable, Prometheus is lightweight relative to Grafana/Loki/InfluxDB already running.

## Update — 2026-08-29
Config prepared in advance, still NOT active: `ingress/caddy/` (Caddyfile +
docker-compose.yml + README explaining exactly when/how to activate).
Written because the "revisit" trigger above is a real question a
developer coming from EC2/bash-managed infra will ask before touching a
VM with a public IP — better answered with a validated config on the
shelf than from scratch under pressure. `caddy validate` passes. Not
referenced by `terraform/modules/oci-compute/cloud-init.yaml.tpl` or any
active provisioning path — activation still requires the explicit steps
in `ingress/caddy/README.md` (opening :80/:443, DNS change, etc).

## References
- ADR 007 — Oracle Free Tier (resource budget context)
- `docs/reference/observability-contract.md` — update once Prometheus scrape config lands
- `ingress/caddy/` — prepared, inactive Caddy config for if/when this gets revisited
