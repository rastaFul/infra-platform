# ADR 005 — Environment Strategy: Local → Free-Tier Cloud → Paid Cloud

**Status:** ACCEPTED
**Date:** 2026-08-27
**Deciders:** rodrigob.dev@gmail.com

---

## Context

Every real gate (build, test, `docker build`, compose validation) must run locally before anything is promoted. At the same time, the platform needs at least one real cloud target to validate deployment mechanics (Terraform provisioning, Coolify deploys, DNS/tunnel wiring) before committing budget to AWS. Running two unrelated setups (local ad hoc + cloud ad hoc) risks drift and duplicated config.

## Decision

Three environments, same artifacts, never duplicated definitions:

| Environment | Where | Scheduler | Cost | Purpose |
|---|---|---|---|---|
| `local` | WSL2 (this machine) | Docker Compose (direct) | $0 | Dev loop. All gates run here first. No cloud dependency. |
| `oci-free` | Oracle Cloud Always Free (ARM) | Coolify (git-push deploy) | $0 | First real cloud target. Validates the whole deploy pipeline (Terraform, Coolify, Cloudflare Tunnel, Vault) before spending money. |
| `aws-prod` | AWS | ECS Fargate (or Coolify on EC2, TBD) | Paid | Production, once a project has real revenue/users that justify it. |

**Rule: promotion only, never duplication.**
- `infra-platform/platform/docker-compose.yml` is the single definition of the shared platform stack (Vault, OTEL Collector, Prometheus, Grafana, Loki, InfluxDB). It runs unmodified in `local` and `oci-free` — same file, different environment.
- Each app's `Dockerfile` and `docker-compose.yml` are equally environment-agnostic. Only environment variables/secrets differ per environment (`.env` locally, Vault + Coolify env vars in `oci-free`).
- No environment reads another's telemetry. Local dev noise never reaches the `oci-free` Grafana/GlitchTip — each environment runs its own instance of the same stack definition.

**Promotion pipeline:**
```
push → CI (GitHub Actions: lint, test, build, docker build) → merge to main
     → CD builds+tags image (sha + latest) → pushed to GHCR
     → Coolify deploys tagged image to oci-free
     → (future) same image promoted to aws-prod after validation window
```
No build ever happens directly against a cloud target — only pre-validated images get deployed.

## Consequences

**Positive:**
- Local dev loop is never blocked by cloud availability or cost.
- `oci-free` proves the entire pipeline (IaC, secrets, CD, ingress) at zero cost before AWS spend starts.
- Moving to `aws-prod` later is a target change, not a rewrite — same images, same compose definitions, same promotion pipeline.

**Negative:**
- Running the same stack twice (local + oci-free) consumes local dev machine resources whenever both are up. Acceptable — local platform stack is optional/on-demand, not required for day-to-day app dev.

## References
- ADR 001 (Docker Compose over K8s) — same Compose-to-ECS conceptual mapping applies to Compose-to-Coolify
- ADR 006 (CI/CD split — Coolify)
- ADR 007 (Oracle Free Tier as Phase 1 landing zone)
