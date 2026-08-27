# infra-platform

Central infrastructure repository for the rastaful.dev multi-project platform.

Each project (vetcare, rastafinancas, microgrow, artists) is treated as an independent tenant with isolated networks, isolated Vault secret paths, and isolated Docker networks.

## Architecture

```
services/platform/          ← Grafana, InfluxDB, Loki, GlitchTip (existing)
infra-platform/platform/    ← Vault, OTEL Collector (this repo)
projects/*/                 ← Per-app infra stubs
terraform/modules/          ← Reusable Terraform modules (ECS, VPC, ECR, RDS, Cloudflare)
observability/              ← Grafana dashboards and alert rules
docs/                       ← Diátaxis documentation
```

## Quick Start

```bash
# 1. Configure secrets
cp ~/projects/services/platform/.env.example ~/projects/services/platform/.env
# Edit .env and fill in all passwords/tokens

# 2. Start the full stack
bash scripts/platform-start.sh

# 3. Verify
curl -sf http://localhost:3010/api/health && echo "Grafana OK"
curl -sf http://localhost:8200/v1/sys/health | jq '{initialized,sealed}'
curl -sf http://localhost:8888/metrics | head -3
```

Full setup instructions: [docs/tutorials/01-local-setup.md](docs/tutorials/01-local-setup.md)

## Platform Services

| Service        | URL                     | Purpose |
|----------------|-------------------------|---------|
| Grafana        | http://localhost:3010   | Metrics dashboards |
| Loki           | http://localhost:3100   | Log aggregation |
| InfluxDB       | http://localhost:8086   | Time-series metrics |
| GlitchTip      | http://localhost:8010   | Error tracking |
| Vault          | http://localhost:8200   | Secret management |
| OTEL Collector | http://localhost:4318   | Telemetry gateway |

## Projects

| Project         | Ports           | Network |
|----------------|-----------------|---------|
| vetcare         | 3004            | vetcare_net |
| rastafinancas   | 3000 (web), 3001 (api) | rastafinancas_net |
| microgrow       | 3002, 3003, 4000 | microgrow_net |
| artists         | 3005 (web), 3006 (api) | artists_net |

## Documentation

- [Tutorials](docs/tutorials/) — step-by-step guides for getting started
- [How-To](docs/how-to/) — task-oriented guides for specific operations
- [Reference](docs/reference/) — contracts, module specs, network topology
- [Explanation](docs/explanation/) — ADRs and architectural rationale

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/platform-start.sh` | Start full platform stack (services/platform + infra-platform) |
| `scripts/platform-stop.sh` | Stop all platform services |
| `scripts/vault-init.sh` | Initialize Vault, create AppRoles per project (idempotent) |

## Key Design Decisions

- [ADR 001](docs/explanation/adr/001-docker-compose-over-k8s.md) — Docker Compose over Kubernetes for Phase 0
- [ADR 002](docs/explanation/adr/002-vault-self-hosted.md) — Vault self-hosted for secret management
- [ADR 003](docs/explanation/adr/003-otel-collector-pattern.md) — OTEL Collector as observability gateway
- [ADR 004](docs/explanation/adr/004-multi-cloud-cloudflare-switch.md) — Cloudflare as universal ingress layer
