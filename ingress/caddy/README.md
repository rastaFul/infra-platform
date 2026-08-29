# Caddy — prepared, NOT active

## Status: standby, zero references from any active provisioning path

This exists so the answer to "what if we ever drop Cloudflare Tunnel and
need our own reverse proxy" is a tested config, not a blank page. It is
**not** wired into `terraform/modules/oci-compute/cloud-init.yaml.tpl`,
not deployed anywhere, not part of any `docker compose up` that runs
today.

## Why it exists

`ADR-009` considered this exact question (local Caddy layer in front of
app services) and deferred it: Cloudflare Tunnel already handles TLS,
WAF, and DDoS for free, and `multi-cloud-strategy.md` keeps Cloudflare as
the routing layer through every planned phase (local → `oci-free` →
`aws-prod` → multi-cloud) — the tunnel just relocates, it's never
removed. So there is no current need.

The decision also said: *"Revisit only if a concrete need appears (e.g.
local rate-limiting, canary routing) that Cloudflare doesn't cover."*
This directory is that revisit, done in advance and shelved — writing it
once now, correctly, costs nothing and removes the temptation to rush it
later under pressure.

## When to actually activate this

Only if a concrete reason shows up to drop Cloudflare Tunnel as ingress
(e.g. wanting zero dependency on a third-party edge, or a Cloudflare
feature gap). If that happens:

1. Open `:80`/`:443` on the target host's firewall (`ufw`) and cloud
   security list (currently SSH-only by design, both places — see
   `terraform/modules/oci-compute/main.tf` security list and
   `cloud-init.yaml.tpl`'s `ufw` rules).
2. Point DNS (`A`/`AAAA`, not `CNAME` to `cfargotunnel.com`) at the host's
   public IP.
3. `docker compose up -d` in this directory.
4. Stop routing those hostnames through the Cloudflare Tunnel config
   (`tunnel/cloudflared/config.yml` — remove the matching `ingress`
   entries so nothing double-routes).
5. Verify each hostname with a real `curl`, not just "container Up" —
   same lesson as the tunnel migration incident in
   `.specs/features/local-boot-persistence/spec.md`.

## Why `network_mode: host` + `localhost:PORT`

Mirrors exactly how the Cloudflare Tunnel container reaches app ports
today (`host.docker.internal` → `127.0.0.1:PORT`, see
`docs/reference/network-topology.md`'s port map). Reusing the same
target ports in the `Caddyfile` means activating this later requires
zero changes to any per-project `docker-compose.yml` — only a routing
mechanism swap, not a redesign.

## Validated (syntax only, not deployed)

```
docker run --rm -v $(pwd)/Caddyfile:/etc/caddy/Caddyfile:ro caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile
```
