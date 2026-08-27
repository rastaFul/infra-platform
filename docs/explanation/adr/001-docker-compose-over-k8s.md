# ADR 001 — Docker Compose over Kubernetes (Phase 0)

**Status:** ACCEPTED
**Date:** 2026-08-12
**Deciders:** rodrigob.dev@gmail.com

---

## Context

The platform runs approximately 10 processes across 4 projects (vetcare, rastafinancas, microgrow, artists) on a single WSL2 host with 1 developer. The full observability stack (Grafana, InfluxDB, Loki, GlitchTip) plus application services totals ~15 containers.

Kubernetes introduces significant overhead:
- Local: minikube/k3d adds resource contention, slower iteration cycles
- CI: requires cluster provisioning or KIND setup
- Ops: controllers, CRDs, RBAC, kubeconfig management
- Overkill for a single-node, single-developer context

## Decision

Use **Docker Compose** for Phase 0 (local) and Phase 1 (early cloud via ECS Fargate).

Each project owns its `<project>_net` bridge network. Cross-project communication routes through `platform_net` (owned by `services/platform/`). This is the pattern established by microgrow infra.

ECS Fargate is the cloud target: Task Definitions map 1:1 to Compose services, Services map to Deployments. The conceptual gap is minimal.

## K8s Trigger Conditions

Migrate to Kubernetes when ANY of the following is true:

- 3+ replicas needed for a single service (horizontal scaling pressure)
- Multi-team ownership of services (namespace isolation required)
- Client contract requires EKS/GKE (enterprise compliance)
- Canary deployments with traffic splitting needed at L4/L7

## Consequences

**Positive:**
- Zero cluster overhead — `docker compose up -d` on any machine
- Iteration speed: change → rebuild → up in seconds
- Ops burden near zero for 1 developer
- Patterns are transferable: Compose service = ECS Task Definition, Compose network = VPC subnet

**Negative:**
- No built-in horizontal scaling (manual replica management)
- No rolling update strategy (stop-start only)
- Migration to K8s later requires rewriting deployment descriptors

## References

- [ECS Task Definition vs Kubernetes Pod](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)
- `ADR 004` — multi-cloud strategy via Cloudflare (abstracts away the scheduler layer)
