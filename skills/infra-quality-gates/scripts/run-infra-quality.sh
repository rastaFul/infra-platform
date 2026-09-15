#!/bin/bash
# Per-task infra QUALITY gates (fast): tflint, kubeconform, pluto. Returns JSON.
#
# Companion to code-gates/scripts/run-gates.sh, but for infra QUALITY, not
# SECURITY. Security gates (terraform validate, tfsec, checkov, kube-score)
# are a separate, already-existing bundle — this script does not duplicate
# them.
#
# Cadence: run AFTER each task (harness-infra.md rule 2, "AFTER each task"),
# same point where terraform validate/tfsec/checkov/kube-score already run.
#
# Limitation shared by kubeconform and pluto in this script: raw Helm chart
# templates (files under a chart's templates/ dir) contain Go template syntax
# and are not valid YAML/JSON on their own. This script only scans plain
# manifest YAML/YAML — it deliberately excludes templates/ directories. To
# validate a Helm chart, render it first (`helm template chart/ > rendered.yaml`)
# and point this script (or the tool directly) at the rendered output.
set -euo pipefail
DIR="${1:-.}"
cd "$DIR"

RESULT='{"timestamp":"'$(date -Iseconds)'","gates":{},"overall":"PASS"}'

# --- tflint: Terraform lint (unused vars, naming conventions, provider best practices) ---
TF_FILES=$(find . -maxdepth 6 -name "*.tf" -not -path "*/.terraform/*" 2>/dev/null | head -1)
if [ -z "$TF_FILES" ]; then
  TFLINT_STATUS="SKIPPED"; TFLINT_ERRORS=0; TFLINT_WARNINGS=0; TFLINT_NOTE="no .tf files found"
elif ! command -v tflint &>/dev/null; then
  TFLINT_STATUS="SKIPPED"; TFLINT_ERRORS=0; TFLINT_WARNINGS=0; TFLINT_NOTE="tflint not installed"
else
  tflint --init >/dev/null 2>&1 || true
  TFLINT_OUT=$(tflint --recursive --format json 2>&1) && TFLINT_STATUS="PASS" || TFLINT_STATUS="FAIL"
  TFLINT_ERRORS=$(echo "$TFLINT_OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(sum(1 for i in d.get('issues',[]) if i.get('rule',{}).get('severity')=='error'))" 2>/dev/null || echo 0)
  TFLINT_WARNINGS=$(echo "$TFLINT_OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(sum(1 for i in d.get('issues',[]) if i.get('rule',{}).get('severity')=='warning'))" 2>/dev/null || echo 0)
  [ -z "$TFLINT_ERRORS" ] && TFLINT_ERRORS=0
  [ -z "$TFLINT_WARNINGS" ] && TFLINT_WARNINGS=0
  [ "$TFLINT_ERRORS" -gt 0 ] 2>/dev/null && TFLINT_STATUS="FAIL"
  TFLINT_NOTE=""
fi
RESULT=$(echo "$RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);d['gates']['tflint']={'status':'$TFLINT_STATUS','errors':$TFLINT_ERRORS,'warnings':$TFLINT_WARNINGS,'note':'$TFLINT_NOTE'};print(json.dumps(d))")

# --- kubeconform: validate K8s manifests against real API schemas ---
# Real bug found 2026-09-15 (D-2026-09-15-2/3, item 8): once kubeconform
# actually got installed (previously SKIPPED locally for lack of the
# binary), this glob-every-yaml approach fed it docker-compose.yml,
# GitHub Actions workflows, Grafana/Prometheus/Loki configs, etc. -- every
# single one failed with "missing 'kind' key", a 100% false-positive FAIL
# on a repo (infra-platform) that has zero actual Kubernetes manifests
# (see ADR-001: K8s not adopted yet). Fixed by pre-filtering to files that
# actually look like k8s manifests (grep both `apiVersion:` and `kind:` --
# a cheap heuristic, but every real manifest has both and no non-k8s YAML
# in this repo happens to have both together).
find_k8s_manifest_candidates() {
  # `|| true` on each stage: grep -l legitimately exits 1 when nothing
  # matches (e.g. a repo with zero k8s manifests, like this one today) --
  # under `set -euo pipefail` that would otherwise abort the whole script.
  find . -maxdepth 6 \( -name "*.yaml" -o -name "*.yml" \) -not -path "*/.terraform/*" -not -path "*/node_modules/*" -not -path "*/templates/*" 2>/dev/null \
    | { xargs -r grep -lE '^apiVersion:' 2>/dev/null || true; } \
    | { xargs -r grep -lE '^kind:' 2>/dev/null || true; }
}
K8S_FILES=$(find_k8s_manifest_candidates | head -1)
if [ -z "$K8S_FILES" ]; then
  KCF_STATUS="SKIPPED"; KCF_VALID=0; KCF_INVALID=0; KCF_ERRORS=0; KCF_NOTE="no plain k8s manifest yaml/yml found (raw Helm templates excluded, see script header)"
elif ! command -v kubeconform &>/dev/null; then
  KCF_STATUS="SKIPPED"; KCF_VALID=0; KCF_INVALID=0; KCF_ERRORS=0; KCF_NOTE="kubeconform not installed"
else
  KCF_OUT=$(find_k8s_manifest_candidates | xargs kubeconform -summary -output json -ignore-missing-schemas 2>&1) && KCF_STATUS="PASS" || KCF_STATUS="FAIL"
  KCF_VALID=$(echo "$KCF_OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('summary',{}).get('valid',0))" 2>/dev/null || echo 0)
  KCF_INVALID=$(echo "$KCF_OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('summary',{}).get('invalid',0))" 2>/dev/null || echo 0)
  KCF_ERRORS=$(echo "$KCF_OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('summary',{}).get('errors',0))" 2>/dev/null || echo 0)
  [ -z "$KCF_VALID" ] && KCF_VALID=0
  [ -z "$KCF_INVALID" ] && KCF_INVALID=0
  [ -z "$KCF_ERRORS" ] && KCF_ERRORS=0
  KCF_NOTE=""
fi
RESULT=$(echo "$RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);d['gates']['kubeconform']={'status':'$KCF_STATUS','valid':$KCF_VALID,'invalid':$KCF_INVALID,'errors':$KCF_ERRORS,'note':'$KCF_NOTE'};print(json.dumps(d))")

# --- pluto: detect deprecated/removed K8s API versions before an upgrade breaks ---
if ! command -v pluto &>/dev/null; then
  PLUTO_STATUS="SKIPPED"; PLUTO_DEPRECATED=0; PLUTO_REMOVED=0; PLUTO_NOTE="pluto not installed"
else
  PLUTO_OUT=$(pluto detect-files -d . -o json 2>&1) && PLUTO_STATUS="PASS" || PLUTO_STATUS="FAIL"
  PLUTO_DEPRECATED=$(echo "$PLUTO_OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(sum(1 for i in (d.get('items') or []) if i.get('deprecated')))" 2>/dev/null || echo 0)
  PLUTO_REMOVED=$(echo "$PLUTO_OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(sum(1 for i in (d.get('items') or []) if i.get('removed')))" 2>/dev/null || echo 0)
  [ -z "$PLUTO_DEPRECATED" ] && PLUTO_DEPRECATED=0
  [ -z "$PLUTO_REMOVED" ] && PLUTO_REMOVED=0
  PLUTO_NOTE=""
fi
RESULT=$(echo "$RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);d['gates']['pluto']={'status':'$PLUTO_STATUS','deprecated':$PLUTO_DEPRECATED,'removed':$PLUTO_REMOVED,'note':'$PLUTO_NOTE'};print(json.dumps(d))")

# Overall (SKIPPED gates never fail the run; only FAIL does)
echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d['gates'].values():
    if g['status']=='FAIL': d['overall']='FAIL'; break
print(json.dumps(d,indent=2))
"
