# Infra Quality Gates

Infra QUALITY gates (linting, docs currency, best-practice scoring, schema
validation, deprecated-API detection, real behavioral testing). This is a
separate bundle from infra SECURITY gates (`terraform validate`, `tfsec`,
`checkov`, `kube-score`, `trivy`, all already in `docker/Dockerfile.sandbox`
and documented in `harness-gates/references/policies.md`). Before this
skill, infra QUALITY gate coverage was zero — only security scanning existed.

## Cadence — maps to `harness-infra.md` rule 2

- **Per-task** (runs "AFTER each task", same point as terraform
  validate/tfsec/checkov/kube-score today): `scripts/run-infra-quality.sh` —
  tflint, kubeconform, pluto. Fast, static, safe to run after every task.
- **Final** (runs "WHEN FINISHING all tasks", same point as the final
  re-run of ALL gates): `scripts/run-infra-quality-final.sh` —
  terraform-docs (check mode), Polaris, kube-linter. Slower / more holistic,
  reserved for the final pass.
- **Per-project setup, not a script** (see "Behavioral testing" below):
  terratest, helm-unittest.

Register results in `.specs/audit/execution.md` alongside the existing
security gate results, same format:
```
## Task N: [name] — [timestamp]
- tflint: PASS|FAIL|SKIPPED (N errors, N warnings)
- kubeconform: PASS|FAIL|SKIPPED (N valid, N invalid, N errors)
- pluto: PASS|FAIL|SKIPPED (N deprecated, N removed)
```
and at final validation:
```
- terraform_docs: PASS|FAIL|SKIPPED (N/N modules current)
- polaris: PASS|FAIL|SKIPPED
- kube_linter: PASS|FAIL|SKIPPED (N reports)
```

## Known gap this closes: kube-linter

`claude/.claude/agents/harness-infra.md` (rule 3, "Verification is
external") cites `kube-linter` alongside `kube-score` as a Kubernetes
verification tool. It was never added to `docker/Dockerfile.sandbox` — only
`kube-score` was. `run-infra-quality-final.sh` runs kube-linter and, if it's
still missing from the image, reports the gate as `SKIPPED` with an explicit
note pointing back here, rather than silently omitting it or claiming a
pass. The actual fix (adding the binary to the image) is out of scope for
this skill — see the exact install command reported separately; someone
with permission to edit `Dockerfile.sandbox` needs to add it.

## Shared limitation: raw Helm chart templates

kubeconform, Polaris, and kube-linter all validate real Kubernetes
manifests (valid YAML/JSON with concrete field values). Files under a
chart's `templates/` directory are Go template source, not valid YAML on
their own (`{{ .Values.x }}` etc.) — none of these tools can parse them
directly. Both scripts in this skill exclude `templates/` paths from their
file scan for this reason. To validate a chart, render it first:
```
helm template <chart-dir> > /tmp/rendered.yaml
kubeconform -summary -output json /tmp/rendered.yaml
polaris audit --audit-path /tmp/rendered.yaml --format json
kube-linter lint /tmp/rendered.yaml --format json
```
This also means `helm` must be present in the sandbox image for the
Kubernetes quality gates to be usable against actual charts — see "Missing
base dependencies" reported separately; `helm` is not currently in
`Dockerfile.sandbox` at all (also relevant to the existing `helm
lint`/`helm template` gates cited in `harness-infra.md` rule 3, which have
the same unmet dependency today).

---

## tflint

**What it checks**: Terraform-specific lint — unused declared variables and
locals, naming convention violations, deprecated syntax, and
provider-specific best practices (via provider plugins, e.g.
`tflint-ruleset-aws`). Complements `terraform validate` (which only checks
syntax/internal consistency) and `tfsec`/`checkov` (which check security
posture, not code quality).

**When it runs**: per-task (`run-infra-quality.sh`).

**Command**: `tflint --recursive --format json` (after `tflint --init` to
pull configured provider rulesets, best-effort — a missing `.tflint.hcl`
just means the default ruleset runs).

**PASS criteria**: no issues with `rule.severity == "error"`. This is
tflint's own severity classification — warnings and notices do not fail
the gate by default, matching tflint's own defaults (not an invented
threshold).

**Known limitations**: requires network access on first run if
`.tflint.hcl` declares plugin-based rulesets (they're downloaded, not
bundled). Findings depend entirely on whatever `.tflint.hcl` the project
provides; with no config file, only tflint's built-in "terraform" ruleset
runs (no provider-specific checks).

## terraform-docs

**What it checks**: whether a module's `README.md` documentation (inputs,
outputs, providers, resources) is current with the actual `.tf` source —
not whether docs exist at all (first-time generation is a different,
explicit action, not something this gate silently does).

**When it runs**: final (`run-infra-quality-final.sh`).

**Command**: for every directory containing `.tf` files that already has a
`README.md`: `terraform-docs markdown table --output-file README.md
--output-check <dir>`. `--output-check` is terraform-docs's own built-in
flag for comparing generated output against the existing file without
writing to it — the gate never regenerates docs silently.

**PASS criteria**: `--output-check` reports no diff for every module
checked. A module with `.tf` files but no `README.md` yet is reported
`SKIPPED` (nothing to check currency against) rather than FAIL — bootstrapping
docs for a module for the first time is a task action, not a gate failure.

**Known limitations**: exact CLI flag placement (`markdown table` vs a
`.terraform-docs.yml` config file driving format) should be verified
against the installed terraform-docs version before relying on this in
production — see "Open questions" in the delivery notes. Only checks
modules with an existing `README.md`; doesn't enforce that every module
*must* have one.

## Polaris

**What it checks**: Kubernetes manifest best practices — resource
requests/limits, health checks, security context, image tags/pull policy,
networking — scored against Polaris's built-in rule set. Complements
`kube-score` (different rule set and scoring model, useful to run both).

**When it runs**: final (`run-infra-quality-final.sh`).

**Command**: `polaris audit --audit-path <dir> --format json
--set-exit-code-on-danger`.

**PASS criteria**: Polaris's own exit code, driven by
`--set-exit-code-on-danger` — fails only on results at Polaris's own
"danger" severity (its highest built-in severity level), not on a
score number invented for this gate. Polaris's default scoring output (a
0-100 score) is not used as a pass/fail threshold here since no default
minimum score is defined by the tool itself; the script parses
`DangerResultCount`/`WarningResultCount` best-effort as informational
context only — the exit code is authoritative.

**Known limitations**: JSON field names for the score/count summary should
be verified against the installed Polaris version (schema has changed
across versions); the script's parse is best-effort and falls back to `0`
silently if the shape doesn't match, so treat those two numbers as
informational, not authoritative. Same raw-Helm-template limitation as
kubeconform (see above).

## pluto

**What it checks**: Kubernetes API versions in manifests that are
deprecated or already removed in a target Kubernetes version — catches
"this manifest will break on the next cluster upgrade" before it happens.

**When it runs**: per-task (`run-infra-quality.sh`) — cheap enough to run
every task, and catching this early (before a PR/upgrade) is the entire
point of the tool.

**Command**: `pluto detect-files -d . -o json`.

**PASS criteria**: pluto's own exit code. By default pluto's detect
commands exit non-zero when they find APIs it considers a problem for the
target Kubernetes version; the gate does not add its own
deprecated-vs-removed count threshold on top of that.

**Known limitations**: accuracy depends on pluto's bundled version-mapping
data being current for the Kubernetes version actually in use; if pluto
hasn't been updated in a while it may miss newly-deprecated APIs from
recent Kubernetes releases. Detects from manifest files only, not from a
live cluster.

## kubeconform

**What it checks**: validates Kubernetes manifests against the real
upstream OpenAPI schemas for the target Kubernetes API version (as opposed
to `kube-score`/`kube-linter`/Polaris, which check best practices, not
schema correctness) — catches typos'd fields, wrong types, and manifests
that simply wouldn't be accepted by the API server.

**When it runs**: per-task (`run-infra-quality.sh`).

**Command**: `kubeconform -summary -output json -ignore-missing-schemas
<files>`. `-ignore-missing-schemas` is kubeconform's own flag for CRDs and
other resource types with no published upstream schema — without it,
projects using CRDs would fail on schema-not-found rather than on actual
invalid manifests, which isn't what this gate is checking for.

**PASS criteria**: kubeconform's own exit code (non-zero when
`summary.invalid > 0` or `summary.errors > 0`).

**Known limitations**: raw Helm chart templates limitation (see above,
shared). `-ignore-missing-schemas` means genuinely unknown/misspelled
`kind`/`apiVersion` combinations for CRDs are silently skipped rather than
flagged — that's a deliberate tradeoff of the flag, not a bug in this gate.

## kube-linter

**What it checks**: Kubernetes manifest best practices via a large default
rule set (missing resource limits, running as root, mutable tags, missing
liveness/readiness probes, etc.) — StackRox's rule set, distinct from both
Polaris's and `kube-score`'s.

**When it runs**: final (`run-infra-quality-final.sh`). **This closes the
documented install gap** — see "Known gap this closes" above.

**Command**: `kube-linter lint <dir> --format json`.

**PASS criteria**: kube-linter's own exit code (non-zero when any check in
its default rule set fails — no custom rule-set threshold added here).

**Known limitations**: same raw-Helm-template limitation as kubeconform and
Polaris. Not installed in `Dockerfile.sandbox` today — see delivery notes
for the exact install command needed to close this.

---

## Behavioral testing: terratest and helm-unittest

These two are **not** static scanners and there is no single reusable
script that can run them generically the way the six tools above work —
they are real test suites that must be written per project, the same way
Jest tests are written per project for application code. A generic script
that just runs "terratest" or "helm-unittest" with no test files behind it
would either do nothing or fail with "no tests found", which is not a
useful gate. This section documents the setup pattern; it is intentionally
not a script.

### terratest (per-project setup)

Go-based library (`github.com/gruntwork-io/terratest`) for real
integration testing of infra: actually run `terraform apply` (or `helm
install`, or `kubectl apply`) against a real (usually ephemeral/sandboxed)
environment, assert on the real outcome (a load balancer actually
responding, a bucket actually existing with the right policy, an EKS node
actually joining), then tear it down. This is the "zero behavioral
testing" gap mentioned in this initiative — everything else in this skill
and the security bundle is static analysis; terratest is the only thing
that exercises real infra.

Setup pattern, per project:
1. `test/` directory at the project root (terratest convention), containing
   `*_test.go` files, one per module/stack under test.
2. `go.mod` in `test/` (or project root) declaring the module and
   `require github.com/gruntwork-io/terratest`.
3. Each test: `terraform.InitAndApply(t, opts)` → assertions via terratest
   helpers or plain Go `testing` assertions → `defer terraform.Destroy(t,
   opts)`.
4. Run: `go test -v ./test/... -timeout 30m` (timeouts matter — these tests
   provision real infra and can be slow).
5. Requires real credentials/permissions for whatever is being tested
   (cloud account, cluster context) — this is inherently different from
   the static gates above, which need no credentials. Treat terratest runs
   as needing the same blast-radius/approval discipline as any other
   `terraform apply` (harness-infra.md rule 2/9 — dry-run, checkpoints,
   circuit breaker) since it *is* a real apply.
6. **Requires the Go toolchain in the image** — not present in
   `Dockerfile.sandbox` today (see "Missing base dependencies").

### helm-unittest (per-project setup)

A `helm` plugin (`helm-unittest/helm-unittest`) for unit-testing chart
templates by rendering them against fixture values and asserting on the
rendered output — without a real cluster. Faster and narrower in scope
than terratest; complements Polaris/kubeconform/kube-linter (which check
*rendered* output for correctness/best-practice) by checking that
*templating logic itself* (conditionals, `range`, `required`, helpers)
produces the expected output for given input values.

Setup pattern, per chart:
1. `tests/` directory inside the chart (helm-unittest convention:
   `<chart>/tests/*_test.yaml`).
2. Each test file: a set of cases, each with `values:` (or `set:`)
   overrides and `asserts:` (e.g. `isKind`, `equal`, `contains`,
   `hasDocuments`) against the rendered template.
3. Run per chart: `helm unittest <chart-dir>`. Run across all charts:
   `helm unittest charts/*` (or loop in CI).
4. **Requires the `helm-unittest` plugin installed** on top of `helm`
   itself: `helm plugin install
   https://github.com/helm-unittest/helm-unittest.git`. **Requires `helm`
   in the image first** — not present in `Dockerfile.sandbox` today (see
   "Missing base dependencies").

---

## References

- `scripts/run-infra-quality.sh` — per-task: tflint, kubeconform, pluto.
- `scripts/run-infra-quality-final.sh` — final: terraform-docs (check
  mode), Polaris, kube-linter.
- `../harness-gates/references/policies.md` — existing hard policies and
  the security gate table this bundle complements.
- `../../.claude/agents/harness-infra.md` — orchestrator rules this skill's
  cadence maps to (rule 2), and the source of the kube-linter citation this
  skill closes the install gap for (rule 3).
