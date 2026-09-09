# Policy Gates — OPA/Conftest (policy-as-code)

Turns `harness-gates/references/policies.md` "Hard Policies" from prose the agent promises to follow into rules a deterministic tool blocks on. This was gap #1 in the 2026-09 gate audit: policies existed only as text the LLM read and self-restrained against.

## Why this exists

Everything else in this repo's gates (tsc, eslint, tfsec, checkov...) validates *general* correctness/security. This skill validates *this repo's own opinions* — e.g. "mandatory tags: Environment, Team, App" isn't a CVE, it's a house rule. OPA/Conftest is the right tool for house rules against structured input (Terraform plan JSON, rendered K8s manifests) — tfsec/checkov don't know your org's tagging convention.

## Scope

Only the **structurally checkable** subset of `policies.md` is translated into Rego — rules that can be evaluated from a Terraform plan JSON or a rendered K8s manifest. Process-sequencing rules ("never destroy without approval", "never apply without plan first", "never deploy to prod without passing staging") are CI pipeline ordering concerns, not plan-content — those stay enforced by pipeline structure (see `.github/workflows/gates.yml`), not Rego. Each `.rego` file documents at the bottom exactly what was deliberately left out and why.

## Files

- `policies/terraform.rego` — Cloud + Terraform sections of `policies.md`: no SG 0.0.0.0/0 ingress (unless tagged `public-alb-approved`), no deleting stateful resources without human approval, mandatory tags, no static IAM keys, no public bucket ACLs, encryption-at-rest required.
- `policies/kubernetes.rego` — Kubernetes section: no `:latest` tag, mandatory resource limits, mandatory liveness+readiness probes, Ingress must have TLS.
- `scripts/run-policy-gate.sh` — runs `conftest test` against a Terraform plan JSON and/or a directory of rendered K8s manifests, JSON output matching the `code-gates` style.

## Usage

```bash
# Terraform: generate plan JSON first
terraform plan -out=plan.out && terraform show -json plan.out > plan.json
bash skills/policy-gates/scripts/run-policy-gate.sh plan.json

# Kubernetes: render manifests first
helm template ./chart > /tmp/rendered/all.yaml   # or split per-resource
bash skills/policy-gates/scripts/run-policy-gate.sh "" /tmp/rendered

# Both
bash skills/policy-gates/scripts/run-policy-gate.sh plan.json /tmp/rendered
```

If `conftest` isn't installed, the script returns `SKIPPED` rather than failing silently or fabricating a PASS — this is intentional so a missing tool is visible in the audit trail, not hidden.

## Where this plugs into the flow

- `harness-infra.md` rule 2 "DURING each task": run this gate alongside `terraform plan`/`helm template` dry-run, before any apply.
- Same script, same Rego files, run identically in `.github/workflows/gates.yml` — this is the mechanism that makes local and CI the same test (see repo `RESULT.md` for the overall architecture).

## Setup

Requires `conftest` (OPA-based) in the sandbox image — added to `claude/docker/Dockerfile.sandbox`.

## Extending

New house rule → add a `deny[msg]` rule to the relevant `.rego` file, not a new prose bullet in `policies.md` alone. If it's genuinely un-checkable statically (needs runtime state), document why in the "NOTE — deliberately NOT translated" block instead of faking a rule that never fires.
