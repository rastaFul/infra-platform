# Cost Gates — Infracost

Closes gap #10 from the 2026-09 gate audit: `harness-gates/SKILL.md` pre-gate #5 "Cost Estimation" existed as a bullet point with no tool behind it — "flag for review" with nothing that could actually compute the delta.

## What it does

Runs Infracost against a Terraform plan and reports the monthly cost delta. Deterministic — a diff in dollars, not a judgment call.

## Usage

```bash
bash skills/cost-gates/scripts/run-cost-gate.sh <path-to-terraform-dir>
```

Requires `INFRACOST_API_KEY` env var (Infracost's cloud pricing lookup — free tier exists). If unset, the script returns `SKIPPED`, not a fabricated PASS.

## Threshold — OPEN QUESTION, not decided here

`harness-gates/SKILL.md` says "if cost increase > threshold → flag for review" but never defines the threshold number. This skill does NOT invent one — the script reports the delta and a `status` of `INFO` (not PASS/FAIL) until a real threshold is set. See `.specs/QUESTIONS.md` in this repo.

## Where this plugs into the flow

- `harness-infra.md` rule 2, pre-gate step, alongside `terraform plan` — run after plan, before apply, so cost is known before the human/agent commits to it.
- Same script in `.github/workflows/gates.yml` for PRs that touch `*.tf` files — posts the same numbers, doesn't recompute differently.

## Setup

`curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh` — added to `claude/docker/Dockerfile.sandbox`. Needs `INFRACOST_API_KEY` — see QUESTIONS.md (secret management not decided in this pass).
