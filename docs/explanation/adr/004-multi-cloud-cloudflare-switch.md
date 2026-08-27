# ADR 004 — Cloudflare as Universal Ingress Layer (Multi-Cloud Switch)

**Status:** ACCEPTED
**Date:** 2026-08-12
**Deciders:** rodrigob.dev@gmail.com

---

## Context

The platform deploys across multiple cloud providers over time:
- Phase 0: WSL2 local via Cloudflare Tunnel
- Phase 1: AWS ECS Fargate behind ALB
- Phase 2+: potentially Fly.io, GCP Cloud Run, or VPS for cost optimization

Without a neutral ingress layer, changing clouds requires:
- DNS record updates per service (10+ services)
- Client-side configuration changes
- SSL certificate re-issuance or migration
- Potential downtime during switchover

The platform already uses Cloudflare Tunnel for local exposure.

## Decision

**Cloudflare is the universal ingress/DNS layer.** All public traffic routes through Cloudflare. Changing the cloud provider means changing the origin in Cloudflare DNS — not touching application code or client configurations.

### Routing Pattern

```
Client → Cloudflare (DNS + TLS + WAF)
              ↓
         Origin (DNS CNAME or Tunnel)
              ↓
    ┌─────────────────────┐
    │ AWS ALB             │  ← Phase 1
    │ Fly.io Anycast      │  ← Alternative
    │ GCP Cloud LB        │  ← Alternative
    │ Cloudflare Tunnel   │  ← Local/VPS
    └─────────────────────┘
              ↓
         Container (same Docker image, any cloud)
```

### Migration Procedure (cloud switch)

1. Deploy new containers on target cloud (same Docker image)
2. Verify health at new origin
3. Update Cloudflare DNS origin (or swap Tunnel target)
4. Monitor error rate — rollback: revert DNS origin
5. Decommission old cloud resources

Total downtime: DNS TTL only (set to 60s during migrations).

## Consequences

**Positive:**
- True cloud portability at L7 — apps are cloud-agnostic by design
- WAF, DDoS protection, and TLS managed centrally in Cloudflare
- Zero-downtime migration: run old and new in parallel, shift traffic
- Cloudflare Tunnel enables local/VPS exposure without public IP or open ports

**Negative:**
- Cloudflare becomes a critical path dependency (mitigated: 99.99% SLA)
- All traffic routed through Cloudflare PoPs (latency: +5-20ms, acceptable)
- Cloudflare API access required for Terraform automation (`cloudflare-dns` module)

## Terraform Module

`terraform/modules/cloudflare-dns/` — provisions DNS records and Tunnel configurations per project. This module is the only place that knows which cloud a project's origin lives on.

## References

- [Cloudflare Tunnel docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [Terraform Cloudflare provider](https://registry.terraform.io/providers/cloudflare/cloudflare/latest)
- `terraform/modules/cloudflare-dns/`
