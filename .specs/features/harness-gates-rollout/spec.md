# SPEC — Harness Gates Rollout

## Goal
Install the Harness agent framework + Gate Hardening skill bundle into `infra-platform` itself — the cross-project infra source of truth. Deferred rollout from that initiative (QUESTIONS.md #18). This repo is also where `harness-infra` sessions on OTHER projects go to read ADRs/conventions; installing the agent here means it can be worked on directly with the same gates, not just read from.

## Scope (closed)
IN scope:
- Copy: `CLAUDE.md`, `.claude/agents/*.md`, `skills/`, `steering/`, `templates/dev-quality/`, `.harness-sandbox/docker/` (real copy), `.github/workflows/gates.yml`, `.github/CODEOWNERS` (`@rastaFul`).
- Auto-install: `snip`, `@playwright/mcp`, `claude-auto-retry`, `@lhci/cli` (global tools only — no root `package.json` here, so devDependency-based steps correctly no-op).
- Register rollout in `.specs/project/STATE.md`/`DECISIONS.md`.

OUT of scope / repo-specific notes:
- **No root `package.json`** — dev-quality bundle and `axe-playwright` auto-install correctly skip (report "no package.json").
- **Real Terraform exists here** (`terraform/environments/oci-free/`, `terraform/modules/oci-compute/`) — this is the FIRST time `infra-gates` (terraform validate/tfsec/checkov, tflint/kubeconform/pluto, OPA policy gate, Infracost) will run for real against production-shape Terraform anywhere in this whole initiative (agents-harness itself has no `.tf` files, so that job never actually exercised its Terraform-specific steps before). Expect this to potentially surface new findings or gaps — reported honestly, not silently suppressed. A real FAIL here is informational for this session, not something to force green by loosening a gate.
- `git status` shows pre-existing modified files (`.specs/audit/execution.md`, `.specs/project/DECISIONS.md`, `.specs/project/STATE.md`, `docs/reference/repository-layout.md`) from unrelated prior work — left untouched and unstaged by this rollout's commit; only genuinely new harness-installation paths are staged.
- GitHub admin actions (branch protection, secrets) — separate runbooks, not re-decided here.

## Done criteria
Same as the other rollout specs in this batch: install completes, files present, `bash -n`/`yamllint` PASS, commit contains ONLY harness files (not the repo's pre-existing unrelated modifications), STATE.md/DECISIONS.md updated.

## Autonomous execution parameters
Same as the other rollout specs in this batch (single interactive pass, circuit breaker 3 retries then BLOCKED-and-continue-with-others).

## Outcome — 2026-09-08T22:35:00-03:00
DONE. Installed via `agents-harness/claude/install.sh`: CLAUDE.md, `.claude/agents/`, `skills/`, `steering/`, `templates/dev-quality/`, `.harness-sandbox/docker/`, `.github/workflows/gates.yml`, `.github/CODEOWNERS`. No root `package.json` — devDependency-based steps correctly skipped. Verified: files present, `bash -n`/`yamllint` PASS.

**Deliberately NOT touched**: `.specs/project/STATE.md`, `.specs/project/DECISIONS.md`, `.specs/audit/execution.md`, `docs/reference/repository-layout.md` already had substantial pre-existing uncommitted work (124 lines across the 4 files, from an unrelated prior session) at rollout time. Appending this rollout's own notes to those same files would have mixed two unrelated changes into one commit with no clean way to separate them at `git add` granularity — so this outcome is recorded here instead, and the rollout commit stages ONLY the genuinely new harness-installation paths.
