# Security Gates

Scripts to run deterministic security-scanning gates and return structured JSON results. Same philosophy as `code-gates`: an external tool's exit code / JSON decides PASS/FAIL — the agent never eyeballs a diff and calls it "secure."

## Usage

### Per-step / per-task gates (fast — target: seconds)
```bash
bash skills/security-gates/scripts/run-security-gates.sh [project-dir]
```
Runs: gitleaks (secrets) → trivy fs (filesystem vuln + secret scan) → osv-scanner (SCA). Returns JSON.

Run this after any task that touches dependencies, config files, `.env`-adjacent files, or Terraform/K8s manifests — same cadence as `code-gates/run-gates.sh` (per task, before marking DONE).

### Final gates (after all tasks — slower, fuller coverage)
```bash
bash skills/security-gates/scripts/run-security-final.sh [project-dir]
```
Runs: semgrep (SAST) → trivy config (IaC misconfig) → syft + grype (SBOM generation + vuln scan). Returns JSON.

Run this once at the end of a feature/spec, alongside `code-gates/run-final.sh` — not per task, these are minutes not seconds.

### On-demand, cluster-scoped (not in either script — see below)
```bash
kube-bench run --json
```
CIS Kubernetes Benchmark against a **live cluster**. Not part of the fast or final scripts.

## Why kube-bench is separate

Every other tool in this skill scans **files on disk** in this repo's checkout — no network, no cluster, no credentials required, safe to run in the sandbox on any task. kube-bench is fundamentally different: it runs *inside* the cluster's nodes (as a pod/job, or via SSH to the node) and inspects live kubelet/apiserver/etcd configuration, file permissions, and process flags — not manifests in git. It requires:
- An actual reachable cluster with the right RBAC/node access
- Running as (or alongside) a privileged pod on each node type (control-plane vs worker use different CIS profiles)
- Cluster credentials this repo's sandbox does not have and should not be given implicitly

So it cannot be part of an automated per-task or per-final gate that runs against a plain file checkout. Use it as a manual/scheduled check against a real cluster:

```bash
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
kubectl logs job/kube-bench
# or, targeted:
kube-bench run --targets master,node,etcd,policies --json
```

PASS/FAIL: kube-bench reports PASS/FAIL/WARN per CIS control ID, not a single aggregate. Treat any FAIL on a control this project has not explicitly accepted as blocking; WARN items need human triage (many are informational / require manual verification, e.g. "ensure kubeconfig has restrictive permissions" needs actual node access to confirm). Document accepted exceptions the same way `harness-gates/references/policies.md` documents hard policies — do not silently ignore FAILs.

## Tools covered by the scripts

| Tool | Stage | Scope | What it does |
|------|-------|-------|---------------|
| gitleaks | fast | filesystem, regex+entropy rules | Secret scanning (API keys, tokens, private keys) across tracked/untracked files |
| trivy fs | fast | filesystem | Combined vuln (lockfiles) + secret scan, redundant-by-design with gitleaks/osv-scanner (different rule engines catch different things) |
| osv-scanner | fast | filesystem, multi-ecosystem | SCA against the OSV database (npm, PyPI, Go, Terraform providers, etc.) — broader than `npm audit` alone |
| semgrep | final | source code (TS/JS/Terraform rulesets via `--config auto`) | SAST — pattern-based static analysis, OWASP-ish rules |
| trivy config | final | IaC (Terraform, Dockerfile, K8s manifests, Helm) | Misconfiguration scanning |
| syft + grype | final | filesystem → SBOM → vuln scan | Generates a CycloneDX SBOM (syft), then scans it for known vulnerabilities (grype) — catches transitive/vendored components a lockfile-only scanner can miss |
| kube-bench | on-demand only | live cluster | CIS Kubernetes Benchmark — see above, not scripted here |

## PASS / FAIL criteria

Mirrors the bar already established in `steering/dependency-audit.md` for `npm audit`: **0 critical + 0 high is mandatory**, medium/low is tracked but does not block.

| Gate | FAIL when |
|------|-----------|
| gitleaks | any secret found (no severity concept — a secret is a secret) |
| trivy_fs | any CRITICAL/HIGH vuln, or any secret found |
| osv_scanner | any vuln with `database_specific.severity` CRITICAL or HIGH, **or any `unscored` finding** (fail-closed, treated as HIGH — decided) |
| semgrep | any finding with `extra.severity == ERROR` **or `WARNING`** (decided — both block) |
| trivy_config | any CRITICAL/HIGH misconfiguration (same 0-critical/0-high bar as the other 5 tools — decided, kept uniform for simplicity) |
| sbom_grype | any vuln with grype `severity` Critical or High |

`SKIPPED` (tool not installed) does not fail `overall` — it is reported so the orchestrator can see gate coverage is degraded, not silently treat it as a pass. `ERROR` (tool ran but produced unparseable output, e.g. crashed) **does** fail `overall` — a scanner that didn't run successfully must never be read as "no findings."

## Known limitations

- **osv-scanner severity is not always normalized.** OSV records only reliably carry `database_specific.severity` (CRITICAL/HIGH/MODERATE/LOW) for GHSA-sourced advisories (npm, etc.); some ecosystems only ship a raw CVSS vector string with no qualitative label. Those are counted separately as `unscored` and, per the decision below, **do** block the gate (fail-closed).
- **trivy fs secret scanning overlaps with gitleaks.** Intentional (different detectors, different false-negative profiles), but expect the same leaked secret to sometimes show up in both gate results.
- **semgrep `--config auto`** pulls community/Pro rulesets from the Semgrep Registry at run time — requires network access and is non-deterministic across time (rules get added/updated upstream). If hermetic/offline runs are required later, pin a specific ruleset (e.g. `p/owasp-top-ten`, `p/terraform`) instead of `auto`.
- **semgrep severity taxonomy (ERROR/WARNING/INFO)** is not the same as the CVSS-style critical/high/medium/low used by every other tool here. Both ERROR and WARNING block, per the decision below.
- **syft/grype SBOM scan is filesystem-based (`dir:.`)**, not an image scan — it complements `trivy fs`/`osv-scanner` by resolving transitive dependencies more thoroughly, but does not replace an image scan of the actual built artifact (that remains `trivy image` at container-build time, already covered elsewhere in this repo's Dockerfile-related gates).

## Decisions (QUESTIONS.pt-BR.md, 2026-09 — no longer open)

1. `semgrep` `WARNING`-severity findings **also block**, same as `ERROR`.
2. `osv-scanner` findings with no normalized severity label (`unscored`) **fail-closed** (treated as HIGH).
3. The 0-critical/0-high bar **is uniform** across all six tools — user explicitly preferred keeping IaC misconfig (trivy config) on the same bar as dependency/code vulnerabilities for simplicity, no differential treatment.

## Output Format

```json
{
  "timestamp": "2026-01-01T12:00:00-03:00",
  "gates": {
    "gitleaks": {"status": "PASS", "secrets_found": 0},
    "trivy_fs": {"status": "PASS", "critical": 0, "high": 0, "secrets_found": 0},
    "osv_scanner": {"status": "PASS", "critical": 0, "high": 0, "unscored": 0}
  },
  "overall": "PASS"
}
```

Final-stage output (`run-security-final.sh`) uses the same shape with gates `semgrep`, `trivy_config`, `sbom_grype`.

## Tool installation

None of gitleaks, semgrep, osv-scanner, syft, or grype are installed in `docker/Dockerfile.sandbox` today (verified by reading it directly — it only has terraform/opentofu, checkov, tfsec, kube-score, trivy, sonar-scanner). `trivy` is already present and is reused as-is for `trivy fs` / `trivy config` (same binary, different subcommand — no extra install needed). Exact install lines for the missing tools were reported back to the requester for manual merge into `Dockerfile.sandbox` (not edited by this skill — install method/versions are an infra decision, not something a skill's docs should silently pin).

If a gate script runs in an environment missing a tool, it reports `"status": "SKIPPED"` for that gate rather than failing — but a SKIPPED security gate should be treated as a coverage gap to fix, not a long-term acceptable state.
