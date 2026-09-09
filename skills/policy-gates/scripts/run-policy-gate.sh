#!/bin/bash
# Runs Conftest (OPA) against Terraform plan JSON and/or rendered K8s manifests.
# Returns JSON matching the code-gates style: {"gates": {...}, "overall": "PASS|FAIL"}
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TF_PLAN_JSON="${1:-}"       # path to `terraform show -json plan.out` output, optional
K8S_MANIFEST_DIR="${2:-}"   # path to rendered manifests dir (helm template output), optional

RESULT='{"timestamp":"'"$(date -Iseconds)"'","gates":{},"overall":"PASS"}'

if ! command -v conftest &>/dev/null; then
  echo '{"timestamp":"'"$(date -Iseconds)"'","gates":{"conftest":{"status":"SKIPPED","reason":"conftest not installed"}},"overall":"SKIPPED"}'
  exit 0
fi

TF_STATUS="SKIPPED"; TF_FAILS=0
if [ -n "$TF_PLAN_JSON" ] && [ -f "$TF_PLAN_JSON" ]; then
  if conftest test "$TF_PLAN_JSON" -p "$SKILL_DIR/policies/terraform.rego" 2>&1 | tee /tmp/conftest-tf.out; then
    TF_STATUS="PASS"
  else
    TF_STATUS="FAIL"
    TF_FAILS=$(grep -c "^FAIL" /tmp/conftest-tf.out 2>/dev/null || echo 0)
  fi
fi

K8S_STATUS="SKIPPED"; K8S_FAILS=0
if [ -n "$K8S_MANIFEST_DIR" ] && [ -d "$K8S_MANIFEST_DIR" ]; then
  if conftest test "$K8S_MANIFEST_DIR"/*.yaml -p "$SKILL_DIR/policies/kubernetes.rego" 2>&1 | tee /tmp/conftest-k8s.out; then
    K8S_STATUS="PASS"
  else
    K8S_STATUS="FAIL"
    K8S_FAILS=$(grep -c "^FAIL" /tmp/conftest-k8s.out 2>/dev/null || echo 0)
  fi
fi

python3 -c "
import json
d = json.loads('$RESULT')
d['gates']['conftest_terraform'] = {'status': '$TF_STATUS', 'failures': $TF_FAILS}
d['gates']['conftest_kubernetes'] = {'status': '$K8S_STATUS', 'failures': $K8S_FAILS}
overall = 'PASS'
for g in d['gates'].values():
    if g['status'] == 'FAIL':
        overall = 'FAIL'
        break
d['overall'] = overall
print(json.dumps(d, indent=2))
"
