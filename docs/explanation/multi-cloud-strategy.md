# Multi-Cloud Strategy

## Overview

The platform is designed to run on any cloud provider without application code changes. The abstraction layers that enable this are:

1. **Docker** — same image runs everywhere (ECS, Fly.io, GCP Cloud Run, VPS)
2. **Cloudflare** — universal ingress and DNS (ADR 004)
3. **Vault** — secrets managed centrally, not per-cloud (ADR 002)
4. **OTEL Collector** — telemetry pipeline independent of cloud monitoring tools (ADR 003)
5. **Terraform modules** — cloud-specific resources encapsulated in modules with consistent interfaces

## Phase Roadmap

| Phase | Environment | Scheduler | Ingress | Secrets |
|-------|-------------|-----------|---------|---------|
| 0 | WSL2 local | Docker Compose | Cloudflare Tunnel | Vault file backend |
| 1 | AWS ECS Fargate | ECS + ALB | Cloudflare → ALB | Vault Raft + KMS |
| 2 | Multi-cloud | ECS / Fly.io / GCP | Cloudflare (origin swap) | Vault HA |

## Cloud Switch Playbook

To move a service from AWS to Fly.io (example):

1. `fly deploy` with existing Docker image (no changes)
2. Set environment variables via Fly secrets (or Vault AppRole — preferred)
3. Verify `GET /health` on new origin
4. Update `cloudflare-dns` Terraform module origin for the service
5. `terraform apply` — Cloudflare DNS updated, traffic shifts
6. Monitor error rate in Grafana for 15 minutes
7. Decommission ECS task definition

## Cost Optimization Strategy

Run each project on the cheapest viable cloud for its profile:
- IoT/always-on (microgrow): ECS Fargate Spot
- API-only, bursty (rastafinancas, artists): Fly.io (pay per request)
- Full-stack (vetcare): ECS Fargate (stable baseline)

Cloudflare is the single routing layer — origin changes are invisible to clients.
