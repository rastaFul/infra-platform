# ADR 008 — Terraform Cloud (Free Tier) as Remote State Backend

**Status:** ACCEPTED
**Date:** 2026-08-27
**Deciders:** rodrigob.dev@gmail.com

---

## Context

`.tfstate` must never be committed to git (contains resource IDs, sometimes secrets in plain text) and must not live only on one laptop with no locking — the exact "IaC in name only" trap this whole initiative is trying to close (see: `infra-platform` itself sat uncommitted for 2 weeks, see `.specs/audit/execution.md` 2026-08-27 session). A cloud-specific backend (e.g. AWS S3 + DynamoDB) would also work against the multi-cloud portability goal — it ties state storage to whichever cloud happens to be first.

## Decision

Use **Terraform Cloud (free tier)** as the remote state backend for every environment (`oci-free` now, `aws-prod` later), regardless of which cloud the resources themselves live in.

- One Terraform Cloud organization, one workspace per environment (`oci-free`, `aws-prod`, ...).
- State locking and history included free for personal use.
- Credentials: Terraform Cloud API token stored as a local CLI credential (`terraform login`) — never committed, never in `.tfvars`.

## Consequences

**Positive:**
- State backend is cloud-agnostic — consistent with the portability requirement, doesn't couple state storage to AWS or OCI.
- Free, gives locking (prevents concurrent `apply` corruption) and run history without extra infra to operate.

**Negative:**
- One more external account/dependency (mitigated: free, low operational surface, industry-standard tool).

## References
- ADR 005 — Environment strategy (one workspace per environment)
- ADR 007 — Oracle Free Tier (first workspace: `oci-free`)
