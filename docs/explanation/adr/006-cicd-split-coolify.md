# ADR 006 — CI/CD Split: GitHub Actions (CI) + Coolify (CD)

**Status:** ACCEPTED
**Date:** 2026-08-27
**Deciders:** rodrigob.dev@gmail.com

---

## Context

D5 (2026-08-25) originally bundled CI/CD under "GitHub Actions". On review, CI and CD have different triggers and different risk profiles and should not be the same mechanism:

- **CI** must run on every push/PR, regardless of whether a cloud target exists — it's pure code validation (lint, test, build, `docker build`), zero blast radius.
- **CD** must only run when there's an actual deploy target, must support rollback/approval, and must not require hand-rolled SSH/deploy scripts per repo.

Options considered for CD: raw GitHub Actions (build→push GHCR→SSH→`docker compose up`), Coolify (self-hosted PaaS-like, git-push-to-deploy), ArgoCD/Flux (GitOps — requires Kubernetes, which ADR 001 explicitly defers), Watchtower (auto-pull only, no approval/rollback).

## Decision

**CI: GitHub Actions**, one reusable workflow in `infra-platform` (`workflow_call`), invoked by each of the 5 app repos. Runs on every push/PR to any branch. Steps: lint → test → `tsc --noEmit` → `docker build` (validates the Dockerfile, doesn't push). Never touches infrastructure.

**CD: Coolify**, self-hosted on the `oci-free` VM (ADR 007). Triggered only on merge to `main`. Coolify pulls the image built by CI (tagged `sha` + `latest`, pushed to GHCR) and deploys it. Gives us: environment/secret UI, one-click rollback, deploy history — without requiring Kubernetes.

**Trigger rule (explicit, per user requirement):** local validation and local infra work (this WSL2 machine) never trigger CI/CD. CI activates on push to the GitHub remote. CD activates only on merge to `main` AND only for environments that are actually provisioned (`oci-free` first, `aws-prod` later once it exists).

## Consequences

**Positive:**
- CI has zero infrastructure dependency — can't accidentally deploy anything.
- CD gets rollback/approval without adopting Kubernetes/ArgoCD.
- Coolify config (apps, env vars, domains) is itself git-connected — deploy definitions stay inspectable, not tribal knowledge in a UI.

**Negative:**
- Coolify is one more service to operate (mitigated: it runs on `oci-free`, not locally, and only needs a working Docker host).
- Not a "pure GitOps" setup (no ArgoCD reconciliation loop) — acceptable per ADR 001's K8s trigger conditions, none of which are met yet.

## References
- ADR 001 — Docker Compose over Kubernetes (why no ArgoCD/Flux yet)
- ADR 005 — Environment strategy (where CD actually deploys to)
- ADR 007 — Oracle Free Tier (where Coolify itself runs)
