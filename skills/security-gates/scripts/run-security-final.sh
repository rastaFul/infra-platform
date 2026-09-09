#!/bin/bash
# Run final-stage security gates: semgrep, trivy config, syft+grype (SBOM scan).
# Slower/fuller tools — run once after all tasks, not per-task. Returns JSON.
set -euo pipefail
DIR="${1:-.}"
cd "$DIR"

RESULT='{"timestamp":"'$(date -Iseconds)'","gates":{},"overall":"PASS"}'

# ---- semgrep (SAST — OWASP-ish rulesets for TS/JS/Terraform) ----
if command -v semgrep &>/dev/null; then
  SEMGREP_OUT=$(semgrep --config auto --json --quiet . 2>/dev/null) || true
  SEMGREP_GATE=$(echo "$SEMGREP_OUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception as e:
    print(json.dumps({'status': 'ERROR', 'error_findings': 0, 'warning_findings': 0, 'info_findings': 0, 'error': str(e)}))
    sys.exit()
err = warn = info = 0
for r in (d.get('results') or []):
    sev = (r.get('extra') or {}).get('severity')
    if sev == 'ERROR':
        err += 1
    elif sev == 'WARNING':
        warn += 1
    else:
        info += 1
# DECIDED (QUESTIONS.pt-BR.md #5, 2026-09): both ERROR and WARNING block.
# semgrep's taxonomy (ERROR/WARNING/INFO) isn't the CVSS critical/high/
# medium/low used elsewhere in this repo, but the user chose to include
# WARNING in the blocking bar rather than leave it as a lower tier.
status = 'FAIL' if (err > 0 or warn > 0) else 'PASS'
print(json.dumps({'status': status, 'error_findings': err, 'warning_findings': warn, 'info_findings': info}))
")
else
  SEMGREP_GATE='{"status":"SKIPPED","error_findings":0,"warning_findings":0,"info_findings":0,"reason":"semgrep not installed"}'
fi
RESULT=$(echo "$RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
d['gates']['semgrep'] = json.loads('''$SEMGREP_GATE''')
print(json.dumps(d))
")

# ---- trivy config (IaC misconfiguration: Terraform, Dockerfile, K8s manifests) ----
if command -v trivy &>/dev/null; then
  TRIVY_CFG_OUT=$(trivy config --severity CRITICAL,HIGH --format json --quiet . 2>/dev/null) || true
  TRIVY_CFG_GATE=$(echo "$TRIVY_CFG_OUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception as e:
    print(json.dumps({'status': 'ERROR', 'critical': 0, 'high': 0, 'error': str(e)}))
    sys.exit()
crit = high = 0
for r in (d.get('Results') or []):
    for m in (r.get('Misconfigurations') or []):
        sev = m.get('Severity')
        if sev == 'CRITICAL':
            crit += 1
        elif sev == 'HIGH':
            high += 1
status = 'FAIL' if (crit > 0 or high > 0) else 'PASS'
print(json.dumps({'status': status, 'critical': crit, 'high': high}))
")
else
  TRIVY_CFG_GATE='{"status":"SKIPPED","critical":0,"high":0,"reason":"trivy not installed"}'
fi
RESULT=$(echo "$RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
d['gates']['trivy_config'] = json.loads('''$TRIVY_CFG_GATE''')
print(json.dumps(d))
")

# ---- syft (SBOM) + grype (vuln scan against SBOM) ----
if command -v syft &>/dev/null && command -v grype &>/dev/null; then
  SBOM_FILE=$(mktemp --suffix=.json)
  if syft dir:. -o cyclonedx-json="$SBOM_FILE" >/dev/null 2>&1; then
    GRYPE_OUT=$(grype "sbom:$SBOM_FILE" -o json 2>/dev/null) || true
    GRYPE_GATE=$(echo "$GRYPE_OUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception as e:
    print(json.dumps({'status': 'ERROR', 'critical': 0, 'high': 0, 'error': str(e)}))
    sys.exit()
crit = high = 0
for m in (d.get('matches') or []):
    sev = (m.get('vulnerability') or {}).get('severity')
    if sev == 'Critical':
        crit += 1
    elif sev == 'High':
        high += 1
status = 'FAIL' if (crit > 0 or high > 0) else 'PASS'
print(json.dumps({'status': status, 'critical': crit, 'high': high}))
")
  else
    GRYPE_GATE='{"status":"ERROR","critical":0,"high":0,"reason":"syft SBOM generation failed"}'
  fi
  rm -f "$SBOM_FILE"
else
  GRYPE_GATE='{"status":"SKIPPED","critical":0,"high":0,"reason":"syft and/or grype not installed"}'
fi
RESULT=$(echo "$RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
d['gates']['sbom_grype'] = json.loads('''$GRYPE_GATE''')
print(json.dumps(d))
")

# ---- overall ----
echo "$RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for g in d['gates'].values():
    if g['status'] in ('FAIL', 'ERROR'):
        d['overall'] = 'FAIL'
        break
print(json.dumps(d, indent=2))
"
