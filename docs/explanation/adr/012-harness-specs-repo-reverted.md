# ADR 012 — `harness-specs` Repo Created, Then Reverted (Same Day)

**Status:** ACCEPTED (records a reversal)
**Date:** 2026-08-27
**Deciders:** rodrigob.dev@gmail.com

---

## Context

Earlier the same day, auditing found `~/.specs` (cross-project harness state: `STATE.md`, `DECISIONS.md`, `audit/`, `metrics/`, `features/`) had never been under version control. The fix applied was: `git init` it in place and push it as a new repo, `github.com/rastaFul/harness-specs`.

User asked, correctly: what's the difference between this and `agents-harness`, and why does `.specs` exist in three places (`~/.specs`, `~/projects/.specs`, and inside individual product repos)?

Re-auditing surfaced the real problem: `~/.specs` wasn't a deliberate "cross-project state" location — it was an **accident of working directory**. Every harness session resolves `.specs/` relative to wherever it was launched from. Sessions launched from `~` wrote there; sessions launched from `~/projects/` wrote to `~/projects/.specs`. Both locations mixed genuine cross-repo infra state with per-product feature specs that had simply leaked into the wrong place (`clock-of-clocks` — orphaned, no repo; `microgrow-full-test`/`startup-validation` — belong in `microgrow`; `17-contractor-onboarding`/`short-term` — belong in `artists-booking`).

Turning that accident into a permanent, separately-versioned repo (`harness-specs`) would have **fossilized the mistake** instead of fixing it — a fourth location, no more correct than the first three, just with a git remote attached.

## Decision

Reverted. `harness-specs` repo deleted (local `.git` removed, GitHub repo deleted). Content redistributed to where it actually belongs:

- Cross-repo infra state (`project/STATE.md`, `project/DECISIONS.md`, `audit/execution.md`, `metrics/`, `features/infra-strategy/`, `project/infra-reorg/`) → `infra-platform/.specs/` (this repo already exists, already is the infra source of truth — cross-repo infra state belongs inside it, not in a sibling repo)
- `features/microgrow-full-test/`, `features/startup-validation/` → `microgrow/.specs/features/`
- `features/17-contractor-onboarding/` (from the separate `~/projects/.specs` leak), `features/short-term/` → `artists-booking/.specs/features/`
- `features/clock-of-clocks/` → deleted (no corresponding repo exists, spec was never implemented)

`~/projects/.specs` (the second accidental location) removed entirely after redistribution.

## Consequences

**Positive:**
- No more guessing which `.specs` has the real state — one per repo, resolved correctly because sessions now start inside the right repo (see `repository-layout.md`).
- Admits the mistake in the audit trail rather than hiding it — consistent with "no external verification, no trust": this ADR *is* the external verification catching the orchestrator's own error.

**Negative:**
- Git history from the brief `harness-specs` repo (2 commits, few hours) is lost. Acceptable — the content itself is fully preserved via the redistribution, only the throwaway repo wrapper is gone.

## References
- `docs/reference/repository-layout.md` — the permanent fix (launch sessions from inside the right repo)
