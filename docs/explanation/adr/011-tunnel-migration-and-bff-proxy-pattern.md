# ADR 011 — Tunnel Migrated to infra-platform + BFF-Proxy Public Exposure Pattern

**Status:** ACCEPTED
**Date:** 2026-08-27
**Deciders:** rodrigob.dev@gmail.com

---

## Context

Two questions came up together: (1) should the Cloudflare Tunnel config live in `infra-platform` too, and (2) can only the frontend be publicly exposed, with the backend API still reachable — for security (smaller public attack surface: no direct network path to the API process, no need to CORS-harden it against arbitrary origins, no API rate-limiting/WAF config to duplicate).

Auditing the actual tunnel config in use turned up two more bugs:
- The **live** tunnel (PM2 `platform-tunnel`) used `~/projects/services/tunnel/cloudflared/config.yml`. The tunnel config I'd cited in ADR 007 / `how-to/provision-oracle-free-tier.md` (`~/.cloudflared/config.yml`) was a **different, stale file** — never actually used, missing routes the live one has. Fixed: this ADR is the correction of record.
- `artists.rastaful.dev` returned HTTP 500 in production during this audit — traced to a corrupted pnpm store (`ERR_PNPM_MODIFIED_DEPENDENCY`) causing `ENOENT` on internal Next.js files for `artists-web`. Unrelated to the tunnel/infra work, fixed via `pnpm install --force` + `pm2 restart artists-web`. Confirmed back to 307 (normal) on both direct and public routes.

## Decision — BFF-proxy pattern (already the working pattern, now standardized)

Investigating how each frontend reaches its backend found the answer already implemented in 3 of 4 projects — it just wasn't documented as a deliberate pattern:

```
Browser → https://<project>.rastaful.dev/api/*  (single public hostname)
              │
              └─ Next.js server-side rewrite (next.config.js)
                     │
                     └─ http://localhost:<api-port>/api/*  (never public)
```

- `artists-booking`, `rastafinancas`, `microgrow`: `next.config.js`/`next.config.ts` has an `async rewrites()` block forwarding `/api/*` to the local API port server-side. The browser only ever talks to the frontend's own origin — the API process has **no public hostname in the tunnel at all**, by design, not by omission.
- `vetcare`: monolithic Next.js (API routes are part of the same app) — the question doesn't apply, there's only one process.
- `microgrow`'s MQTT WebSocket (`mosquitto:9001`) was deliberately removed from the tunnel entirely (see comment in `microgrow/infra/mosquitto/mosquitto.conf`) — no public exposure, not proxied either. Confirmed intentional, not a gap.

**Rule going forward:** any new backend service gets a public hostname in the tunnel **only if there's a concrete reason it can't go through its frontend's rewrite proxy** (e.g. a webhook receiver with no frontend in front of it). Default is: frontend hostname only, API proxied server-side.

## Decision — tunnel config lives in infra-platform

Moved `~/projects/services/tunnel/` → `infra-platform/tunnel/`. PM2 process re-registered (`pm2 delete` + `pm2 start` against the new path + `pm2 save`) — confirmed reconnected (QUIC healthy) and all public routes still resolving post-move. `credentials-file` stays at the standard `~/.cloudflared/<tunnel-id>.json` location (cloudflared convention, not duplicated into the repo).

## Consequences

**Positive:**
- Public attack surface per project = 1 hostname (frontend), not 2. API is unreachable from the internet by construction, not by firewall rule that could drift.
- Tunnel config now versioned in the same repo as everything else infra — no more silent divergence between a "live" and a "documented" config.
- Found and fixed a real production outage (`artists.rastaful.dev` 500) as a side effect of actually auditing this instead of trusting the docs.

**Negative:**
- None — this was already the pattern for 3/4 projects, just formalizing + fixing the 1 stale-doc / 1 unrelated bug found along the way.

## References
- ADR 007 — corrects the tunnel config path cited there
- `docs/reference/repository-layout.md` — updated
