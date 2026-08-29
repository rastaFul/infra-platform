# CloudFlare Tunnel

Manages the single CloudFlare tunnel for all local services. Containerized
2026-08-28 (was PM2, see `.specs/features/local-boot-persistence/spec.md`
in this repo) — PM2 doesn't survive WSL2 restarts without systemd, Docker
Compose's `restart: unless-stopped` does.

## Routes

| Hostname | Service | Port |
|----------|---------|------|
| financas.rastaful.dev | rastafinancas-web | 3000 |
| grow.rastaful.dev | microgrow-webapp | 3002 |
| grow-sim.rastaful.dev | microgrow-webapp-sim | 3003 |
| metrics.rastaful.dev | platform-grafana | 3010 |
| artists.rastaful.dev | artists-web | 3005 |
| vetcare.rastaful.dev | vetcare | 3004 |

Every route above is a **frontend** (or Grafana, which has no separate
backend). No API gets a public hostname of its own — see ADR-011
(BFF-proxy pattern): each frontend's `next.config.js` proxies `/api/*`
server-side to its own backend, which is never reachable from the tunnel
directly. `grow-mqtt` and any direct API route were deliberately never
added here — don't add one without a concrete reason the proxy pattern
doesn't fit (say so explicitly if you do).

Ingress targets in `cloudflared/config.yml` point at `host.docker.internal`
because every target above is itself a Docker container publishing to
`127.0.0.1` on the host (see each project's `docker-compose.yml`) — this
container reaches the host the same way `platform/docker-compose.yml`'s
otel-collector/prometheus/grafana already do.

## Start

```bash
cd infra-platform/tunnel
docker compose up -d
```

## Credentials

Tunnel credentials remain at `~/.cloudflared/` (managed by cloudflared,
cloudflared's own convention, never versioned) — bind-mounted read-only
into the container by `docker-compose.yml`.

## Cloud Migration

When moving to AWS:
- Replace with ALB + Route53 + CloudFront
- Each service gets its own target group
- ACM manages TLS certificates
- WAF rules replace CloudFlare security features
