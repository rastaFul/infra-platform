# Security Model

## Principles

1. **Tenant isolation by default** — each project is a separate security domain. Cross-tenant access is structurally denied at the Vault policy layer, not just by convention.
2. **Least privilege** — AppRole tokens grant read-only access to a single secret path. No project has write access to its own secrets (secrets are managed by the platform operator, not by apps).
3. **No secrets in environment files** — `.env` files contain only non-sensitive config (ports, feature flags). Secrets are fetched from Vault at runtime.
4. **Defense in depth** — Vault policies explicitly deny cross-tenant paths even though Vault's default is implicit deny. The explicit deny prevents accidental policy inheritance.

## Network Isolation

Each project runs on its own Docker bridge network (`<project>_net`). Services that need to reach platform infrastructure (Vault, Loki, OTEL Collector) join `platform_net` as a secondary network.

No project network is directly routable to another project network. Cross-project communication must go through a defined API surface (HTTP), not direct network access.

## Secret Lifecycle

```
Operator (human) → vault write secret/data/<project>/key value=...
                        ↓
App startup → vault login (role-id + secret-id) → short-lived token (TTL: 1h)
                        ↓
App runtime → vault read secret/data/<project>/key → value in memory
                        ↓
Token TTL expires → app must re-authenticate (automatic via SDK)
```

## TLS Boundaries

- External traffic: Cloudflare handles TLS termination (ADR 004)
- Internal Docker network: plain HTTP acceptable (trusted network, no internet exposure)
- Vault: TLS disabled internally (`tls_disable = true`), Cloudflare provides TLS for external Vault UI access if needed

## Audit

Every Vault secret read generates an audit log entry including: timestamp, client token, request path, response status. Audit logs are written to `/vault/logs/vault.log` (persistent volume).
