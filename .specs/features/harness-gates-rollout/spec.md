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

## CI verification — 2026-09-09T06:50:48-03:00
`infra-gates` job correctly FAILS — checkov found 2 REAL findings against production Terraform (`terraform/modules/oci-compute/main.tf`), never checked before this rollout:
- `CKV_OCI_4`: OCI Compute Instance boot volume in-transit data encryption not enabled
- `CKV_OCI_5`: Legacy MetaData service endpoint not disabled

**Not fixed by this rollout** — this is a live, running production compute instance (the OCI free-tier VM). Changing boot-volume encryption or metadata service settings on it may require instance replacement (real blast radius, not a config-only change) — exactly the kind of action that needs its own spec/plan/`terraform plan` review and explicit approval per harness rule 9 escalation criteria, not something to silently patch as a side effect of a gate-rollout task. The gate is working correctly: this is a genuine, previously-unknown gap it surfaced, not a harness bug.

Also flagged (pre-existing, out of scope): this repo's own `reusable-ci.yml` fails the same checkov CKV2_GHA_1 (missing top-level `permissions:`) check that `gates.yml` itself had — not touched, belongs to infra-platform's own CI, not part of this rollout.

4/5 rolled-out repos (artists-booking, microgrow, rastafinancas, vetcare) are fully green. infra-platform is red for a legitimate, real reason.

## Fix applied — 2026-09-09T07:20:07-03:00
User explicitly authorized fixing the 2 real checkov findings ("pode mexer sim nas vulnerabilidade, quero seguir com o ambiente com a melhor qualidade possível"). Added `launch_options { is_pv_encryption_in_transit_enabled = true }` and `instance_options { are_legacy_imds_endpoints_disabled = true }` to `oci_core_instance.this` in `terraform/modules/oci-compute/main.tf`.

Verified before writing (not guessed): fetched the official provider docs (docs.oracle.com/.../core_instance.html) — both fields are Optional, Updatable, **ForceNew: No**, confirming `terraform apply` will update the existing instance in place, not destroy/recreate it. Checked the known "legacy IMDS + cloud-init" gotcha reported in the OCI Terraform provider community for NEW instance launches — not applicable here: this instance already completed its first boot historically, and Ubuntu 24.04's cloud-init has supported OCI's v2 metadata endpoint for years.

External verification, all real tool runs (not self-declared):
- `terraform validate` (local, v1.9.8): PASS
- `tfsec` (via `aquasec/tfsec` docker image): 0 findings (critical/high/medium/low all 0)
- `checkov -d .` (via `bridgecrew/checkov` docker image, excluding the pre-existing out-of-scope `reusable-ci.yml` CKV2_GHA_1 finding): 210 terraform checks passed, 0 failed — **CKV_OCI_4 and CKV_OCI_5 now both PASS** (re-ran scoped to just those 2 checks first to confirm directly)

**NOT applied to the live instance** — this sandbox session has no OCI API credentials or Terraform Cloud token configured (checked: no `~/.terraform.d/credentials.tfrc.json`, no `OCI_*`/`TF_*` env vars). The Terraform code is fixed and verified; running `terraform apply` against the real state needs to happen through whatever process already has real credentials (the user's own environment, or a CI/CD job with a provisioned OCI token) — not something this session can execute.
