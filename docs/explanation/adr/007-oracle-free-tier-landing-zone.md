# ADR 007 — Oracle Cloud Always Free as Phase 1 Landing Zone

**Status:** ACCEPTED
**Date:** 2026-08-27
**Deciders:** rodrigob.dev@gmail.com

---

## Context

None of the 5 projects currently generate revenue. Committing to paid AWS infrastructure before validating the deploy pipeline (Terraform, Coolify, secrets, ingress) is unnecessary spend. At the same time, cloud portability is an explicit project goal (see `multi-cloud-strategy.md`) — both for cost reasons and to build hands-on experience across providers, which does not need to hold in this context.

Options considered:
- **Vercel/Netlify + Render/Railway free tiers** — good for static frontends, but backend free tiers sleep on idle (Render) or no longer have a real free tier (Railway, removed 2023). Not Docker-Compose-native — would require rewriting the deploy model per provider, breaking the portability goal.
- **Fly.io free allowances** — real but small (256MB per VM), not enough to host the shared platform stack (Vault, OTEL, Prometheus, Grafana, Loki, InfluxDB) plus 8 app services.
- **AWS Free Tier (t2/t3.micro)** — 12 months only, 1GB RAM, and defeats the "validate before paying" purpose since it's the same provider as the end goal.
- **Oracle Cloud Always Free (Ampere A1, ARM)** — no time limit, 2 OCPU / 12GB RAM (reduced from 4/24 in June 2026, still by far the most generous always-free compute available), enough to run the full platform stack + Coolify.

## Decision

Use **Oracle Cloud Always Free (Ampere A1 ARM)** as the `oci-free` environment (ADR 005): one VM running Coolify, which manages the shared platform stack and all 8 app services via Docker Compose definitions already validated locally.

- **Region:** the most stable for ARM free-shape provisioning — avoid US regions (frequent "Out of Capacity"), prefer EU/APAC (Frankfurt/Singapore/Tokyo provision in ~5 min per current reports).
- **Ingress:** Cloudflare Tunnel continues unchanged — `cloudflared` relocates from this WSL2 machine to the Oracle VM, no DNS/domain changes, VM's public IP stays unexposed.
- **Images:** identical Docker images used locally (ADR 005) — no Oracle-specific build.
- **Risk accepted:** ARM64 compatibility per image was checked for the platform stack (Vault, OTEL Collector, Prometheus, Grafana, Loki, InfluxDB, Postgres, Mosquitto — all official multi-arch). GlitchTip requires a recent pinned tag (v4.2.4+) for confirmed arm64 support — tag pin required, `:latest` not acceptable here.

## Consequences

**Positive:**
- $0 cost to validate the entire deploy pipeline before AWS spend starts.
- Forces the "cloud-agnostic images" discipline (multi-cloud-strategy.md) to be proven immediately, not assumed.
- Real hands-on OCI experience — first of the multi-cloud portability goals.

**Negative:**
- Reduced 2 OCPU/12GB ceiling (Oracle cut it mid-2026) means the full stack (10 app processes + ~10 platform containers) leaves little headroom — some services (e.g. `vetcare-postgres_test`) may need to stay local-only.
- ARM64 adds a variable to Docker builds not present on the current x86 dev machine — CI must build/validate `linux/arm64` explicitly (buildx), not assume amd64 works.
- Single free VM is a single point of failure for `oci-free` — acceptable, this environment is explicitly not `aws-prod`.

## References
- ADR 005 — Environment strategy
- ADR 006 — CI/CD split (Coolify runs here)
- `multi-cloud-strategy.md` — portability abstraction layers
