# Repository Layout

Standard for where things live under `~/projects/`. Written 2026-08-27 after an audit found duplicated/orphaned infra directories (`~/services/platform` root-owned duplicate, ~1GB of manual pre-Docker binaries in `~/projects/services/`) — this doc exists so that doesn't happen again.

## Rule

`infra-platform` is the **single source of truth** for anything infra-wide: Terraform, the shared platform Compose stack, Vault policies, OTEL config, Grafana dashboards, CI reusable workflows. Nothing infra-wide gets duplicated into another repo.

Each app repo owns only what's specific to itself.

## Layout

```
~/projects/
  infra-platform/                    ← infra source of truth (this repo)
    terraform/
      modules/                       ← one dir per reusable module (vpc, ecs-service, oci-compute, cloudflare-dns, ...)
      environments/                  ← one dir/tfvars per environment (local, oci-free, aws-prod) — see ADR 005
    platform/                        ← shared platform docker-compose.yml (Vault, OTEL, Prometheus, Grafana, Loki, InfluxDB)
    projects/{artists,microgrow,rastafinancas,vetcare}/   ← per-project overlays/values consumed by the platform
    scripts/                         ← platform-start.sh, platform-stop.sh, vault-init.sh
    docs/                            ← Diátaxis: tutorials/, how-to/, reference/, explanation/ (incl. adr/)
    .specs/                          ← this repo's own harness audit trail

  artists-booking/, microgrow/, rastafinancas/, vetcare/  ← app repos
    Dockerfile(s)                    ← owned here, not in infra-platform
    .github/workflows/ci.yml         ← calls infra-platform's reusable CI workflow
    infra/ or infrastructure/        ← app-specific compose (mosquitto, telegraf, promtail, evolution-api, ...)
                                        NOT shared platform services — those live in infra-platform/platform/

~/.specs/                            ← harness cross-repo orchestration state (spans all of the above).
                                        Kept at home root deliberately — it tracks work that spans multiple
                                        repos and shouldn't live inside any single one of them.
```

## What NOT to do

- **Don't** install anything infra-related as raw binaries/tarballs outside Docker. Everything platform-related runs as a container, defined in a `docker-compose.yml`, checked into a repo. (This is exactly what the ~1GB of `grafana.tar.gz`/`influxdb2.tar.gz`/`telegraf.tar.gz` + extracted binaries in `~/projects/services/` was — a pre-Docker-Compose manual bootstrap, `start-microgrow.sh`, fully superseded and removed 2026-08-27.)
- **Don't** create a directory outside `~/projects/` for anything project-related (the old `~/services/platform` duplicate, owned by `root`, was exactly this — orphaned, unreferenced, removed).
- **Don't** put a service specific to one project (e.g. `evolution-api`, WhatsApp integration for `vetcare`) in a generic `services/` folder. It lives at `vetcare/infra/evolution/` — moved there 2026-08-27.
- **Don't** duplicate the platform Compose stack definition per project. Projects reference `platform_net` (external network) to reach the shared stack — they never redefine Vault/Grafana/etc themselves.

## Enforcement

Every new infra decision gets an ADR in `infra-platform/docs/explanation/adr/`. Every new operational procedure gets a how-to in `infra-platform/docs/how-to/`. If it's not documented there, it doesn't count as decided — re-derive it from a session transcript otherwise, which is exactly the rework this doc exists to prevent.
