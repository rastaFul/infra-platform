# Repository Layout

Standard for where things live under `~/projects/`. Written 2026-08-27 after an audit found duplicated/orphaned infra directories. Updated same day after a second, deeper audit found the duplication was worse than first thought — see "History" below.

## Rule

`infra-platform` is the **single source of truth** for anything infra-wide: Terraform, the shared platform Compose stack, the Cloudflare Tunnel, Vault policies, OTEL config, Grafana dashboards, CI reusable workflows. Nothing infra-wide gets duplicated into another repo.

Each app repo owns only what's specific to itself, including its own `.specs/`.

## Layout

```
~/projects/
  infra-platform/                    ← infra source of truth (this repo)
    terraform/
      modules/                       ← one dir per reusable module (vpc, ecs-service, oci-compute, cloudflare-dns, ...)
      environments/                  ← one dir/tfvars per environment (local, oci-free, aws-prod) — see ADR 005
    platform/                        ← ONE shared platform docker-compose.yml: Vault, OTEL Collector,
                                        Prometheus, Grafana, Loki, InfluxDB, GlitchTip — consolidated
                                        2026-08-27, see ADR 010. Volumes pinned via explicit `name:`
                                        (platform_*) so directory renames never orphan data again.
    tunnel/                          ← Cloudflare Tunnel (cloudflared config + PM2 ecosystem) — moved
                                        here 2026-08-27, see ADR 011. credentials-file stays at
                                        ~/.cloudflared/<tunnel-id>.json (not versioned, cloudflared's
                                        own convention).
    projects/{artists,microgrow,rastafinancas,vetcare}/   ← per-project overlays/values consumed by the platform
    scripts/                         ← platform-start.sh, platform-stop.sh, vault-init.sh
    docs/                            ← Diátaxis: tutorials/, how-to/, reference/, explanation/ (incl. adr/)
    .specs/                          ← cross-project harness state (STATE.md, DECISIONS.md, audit,
                                        metrics) for infra work that spans multiple repos. Moved here
                                        2026-08-27 from a standalone `~/.specs` (was its own repo,
                                        `harness-specs` — deleted, was the wrong call, see ADR 012)

  artists-booking/, microgrow/, rastafinancas/, vetcare/  ← app repos
    Dockerfile(s)                    ← owned here, not in infra-platform
    .github/workflows/ci.yml         ← calls infra-platform's reusable CI workflow
    infra/ or infrastructure/        ← app-specific compose (mosquitto, telegraf, promtail, evolution-api, ...)
                                        NOT shared platform services — those live in infra-platform/platform/
    .specs/                          ← THIS project's own feature specs/audit/screenshots — never a
                                        different repo's, never the global home directory's
```

`~/projects/services/` — **removed 2026-08-27** (was the source of the original duplication question). Its `platform/` and `tunnel/` contents both migrated into `infra-platform/` (ADR 010, ADR 011). The empty repo shell was deleted locally; the GitHub repo (`rastaFul/services`) was left alone (not deleted) pending an explicit decision to archive/delete it — ask before doing that, it's not this doc's call.

## Why `.specs` location matters (and how it went wrong twice)

The harness convention is "every session reads `.specs/project/STATE.md`, resolved relative to the current working directory." Running a session from the wrong directory silently writes state to the wrong place. This happened three times before this fix:

1. Sessions launched from `~` (home) wrote to `~/.specs` — meant to hold cross-repo infra state, but also accumulated unrelated per-product feature specs (`clock-of-clocks` — no repo, deleted; `microgrow-full-test`, `startup-validation` — belong to `microgrow`).
2. Sessions launched from `~/projects` (one level above a specific repo) wrote to `~/projects/.specs` — accumulated an `artists-booking` feature (`17-contractor-onboarding`) and `short-term` screenshots that belong there, not here.
3. A previous session (2026-08-27, earlier same day) "fixed" #1 by turning `~/.specs` into its own git repo (`harness-specs`) instead of asking why the content was there in the first place. Wrong call — reverted same day, see ADR 012.

**Fix, permanent:** always launch harness sessions from inside the actual project repo you're working on. `.specs/` then resolves correctly by construction. Cross-repo infra work (the only legitimate case for state that doesn't belong to one repo) uses `infra-platform/.specs/` explicitly — not a fallback location, a deliberate one.

## What NOT to do

- **Don't** install anything infra-related as raw binaries/tarballs outside Docker. Everything platform-related runs as a container, defined in a `docker-compose.yml`, checked into a repo.
- **Don't** create a directory outside `~/projects/<repo>/` for anything project-related.
- **Don't** put a service specific to one project (e.g. `evolution-api`, WhatsApp integration for `vetcare`) in a generic `services/` folder. It lives at `vetcare/infra/evolution/`.
- **Don't** duplicate the platform Compose stack definition per project. Projects reference `platform_net` (external network) to reach the shared stack — they never redefine Vault/Grafana/etc themselves.
- **Don't** run a harness session from the home directory or from `~/projects/` directly — `cd` into the actual repo first. If genuinely cross-repo, use `infra-platform/.specs/` on purpose, not by accident.
- **Don't** create a new repo to hold "state" without asking whether it should just be a directory inside the repo the state is actually about.

## Shared account-level resources (not a container, not in `platform/`)

Some shared infra isn't a container in `platform/docker-compose.yml` — it's a resource on one
account (this user's) that multiple project repos draw on. Cloudflare Tunnel (`tunnel/`) is the
existing example: one tunnel, one account, documented here and in ADR 011, never redefined
per-project. The same pattern applies to:

- **Resend** (transactional email, `resend.com`, external SaaS — no container, nothing to run).
  One account owns the domain `rastaful.dev`, already verified there. Any project can send from
  `<anything>@rastaful.dev` without new DNS work — verification is per-domain, not per-project.
  Convention: **one API key per project**, generated in that same account and named in the Resend
  dashboard after the project (e.g. `rastafinancas`, `artists-booking`), so a key can be revoked or
  rotated per-project without affecting the others. Same isolation pattern already used for
  InfluxDB tokens (`INFLUXDB_TOKEN_MICROGROW`, `INFLUXDB_TOKEN_RASTAFINANCAS` — shared service,
  token scoped per project). Each project stores its own key as `RESEND_API_KEY` in its own
  `.env`/secrets — never checked into a repo, never shared across projects even though the account
  is shared.
  - In use: `rastafinancas` (production, `RESEND_FROM_EMAIL=noreply@rastaful.dev`).
  - Adopting: `artists-booking` (Spec 55, own key, in progress).
  - No entry in `platform/docker-compose.yml` for this — there's nothing to containerize.

If a future shared account-level resource shows up (another SaaS API key, another verified
domain), document it here the same way instead of leaving it for the next session to rediscover
by inspecting a sibling repo from scratch.

## Enforcement

Every new infra decision gets an ADR in `infra-platform/docs/explanation/adr/`. Every new operational procedure gets a how-to in `infra-platform/docs/how-to/`. If it's not documented there, it doesn't count as decided — re-derive it from a session transcript otherwise, which is exactly the rework this doc exists to prevent.
