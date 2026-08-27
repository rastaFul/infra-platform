# ADR 002 — HashiCorp Vault Self-Hosted for Secret Management

**Status:** ACCEPTED
**Date:** 2026-08-12
**Deciders:** rodrigob.dev@gmail.com

---

## Context

The platform requires secret management that:
1. Demonstrates real enterprise-grade security (not `.env` files checked into git)
2. Supports multi-cloud deployment without vendor lock-in
3. Provides audit logs for secret access (compliance requirement)
4. Isolates secrets per project/tenant — cross-project leakage must be structurally impossible

The platform serves as a reference architecture ("enterprise blueprint"), so cosmetic solutions are insufficient.

## Decision

Deploy **HashiCorp Vault OSS** on `platform_net`, accessible to all project services.

Architecture:
- **Phase 0 (local):** file backend (`/vault/data`), single unseal key stored in `~/.vault-init-local`
- **Phase 1 (cloud):** Raft HA backend + AWS KMS auto-unseal
- **Auth method:** AppRole per tenant (one role per project)
- **Secret paths:** `secret/data/<project>/*` — fully isolated
- **Policies:** each project role has read-only access to its own path, explicit deny on all other tenant paths

## Rejected Alternatives

| Option | Rejected Because |
|--------|-----------------|
| Doppler | SaaS lock-in, requires internet, no self-hosted option in free tier |
| AWS SSM Parameter Store | AWS lock-in, breaks multi-cloud strategy (ADR 004) |
| `.env` files | No audit trail, no rotation, secrets in filesystem, high leak risk |
| 1Password Secrets Automation | Paid, SaaS, limited programmatic access in lower tiers |

## AppRole Isolation Model

Each project gets:
- A Vault policy: read `secret/data/<project>/*`, explicit deny on all other tenant paths
- An AppRole: bound to that policy, TTL-limited tokens
- A role-id + secret-id: stored as environment variables in the app's runtime environment

No shared tokens. No wildcards across tenants. Root token revoked after initial setup in production.

## Consequences

**Positive:**
- Audit log on every secret read (who, when, from which IP)
- Token TTL limits blast radius if a secret-id leaks
- Cloud-agnostic: same Vault, different backend in Phase 1
- Demonstrates real enterprise patterns (AppRole, policies, KV v2)

**Negative:**
- Vault must be running before apps can start (dependency)
- Manual unseal after restart in Phase 0 (Phase 1: KMS auto-unseal resolves this)
- Adds operational complexity vs. `.env` files

## References

- [Vault AppRole Auth](https://developer.hashicorp.com/vault/docs/auth/approle)
- [Vault KV v2](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2)
- `scripts/vault-init.sh` — idempotent initialization script
- `platform/vault/policies/` — per-tenant policy files
