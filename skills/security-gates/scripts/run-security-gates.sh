#!/bin/bash
# Run per-step/per-task security gates: gitleaks, trivy fs, osv-scanner. Returns JSON.
# Fast tools only (target: seconds, not minutes) — safe to run after every task.
set -euo pipefail
DIR="${1:-.}"
cd "$DIR"

RESULT='{"timestamp":"'$(date -Iseconds)'","gates":{},"overall":"PASS"}'

# ---- gitleaks (secret scanning) ----
if command -v gitleaks &>/dev/null; then
  GITLEAKS_REPORT=$(mktemp)
  gitleaks detect --source . --no-git --redact \
    --report-format json --report-path "$GITLEAKS_REPORT" \
    --exit-code 0 >/dev/null 2>&1 || true
  GITLEAKS_GATE=$(python3 -c "
import json
try:
    with open('$GITLEAKS_REPORT') as f:
        content = f.read().strip()
    data = json.loads(content) if content else []
    count = len(data) if isinstance(data, list) else 0
    print(json.dumps({'status': 'FAIL' if count > 0 else 'PASS', 'secrets_found': count}))
except Exception as e:
    print(json.dumps({'status': 'ERROR', 'secrets_found': 0, 'error': str(e)}))
")
  rm -f "$GITLEAKS_REPORT"
else
  GITLEAKS_GATE='{"status":"SKIPPED","secrets_found":0,"reason":"gitleaks not installed"}'
fi
RESULT=$(echo "$RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
d['gates']['gitleaks'] = json.loads('''$GITLEAKS_GATE''')
print(json.dumps(d))
")

# ---- trivy fs (filesystem: vuln + secret scan) ----
if command -v trivy &>/dev/null; then
  TRIVY_OUT=$(trivy fs --scanners vuln,secret --severity CRITICAL,HIGH --format json --quiet . 2>/dev/null) || true
  TRIVY_GATE=$(echo "$TRIVY_OUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception as e:
    print(json.dumps({'status': 'ERROR', 'critical': 0, 'high': 0, 'secrets_found': 0, 'error': str(e)}))
    sys.exit()
crit = 0
high = 0
secrets = 0
for r in (d.get('Results') or []):
    for v in (r.get('Vulnerabilities') or []):
        sev = v.get('Severity')
        if sev == 'CRITICAL':
            crit += 1
        elif sev == 'HIGH':
            high += 1
    secrets += len(r.get('Secrets') or [])
status = 'FAIL' if (crit > 0 or high > 0 or secrets > 0) else 'PASS'
print(json.dumps({'status': status, 'critical': crit, 'high': high, 'secrets_found': secrets}))
")
else
  TRIVY_GATE='{"status":"SKIPPED","critical":0,"high":0,"secrets_found":0,"reason":"trivy not installed"}'
fi
RESULT=$(echo "$RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
d['gates']['trivy_fs'] = json.loads('''$TRIVY_GATE''')
print(json.dumps(d))
")

# ---- osv-scanner (multi-ecosystem SCA) ----
if command -v osv-scanner &>/dev/null; then
  OSV_OUT=$(osv-scanner --json -r . 2>/dev/null) || true
  OSV_GATE=$(echo "$OSV_OUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception as e:
    print(json.dumps({'status': 'ERROR', 'critical': 0, 'high': 0, 'unscored': 0, 'error': str(e)}))
    sys.exit()
crit = 0
high = 0
unscored = 0
for result in (d.get('results') or []):
    for pkg in (result.get('packages') or []):
        for vuln in (pkg.get('vulnerabilities') or []):
            sev = (vuln.get('database_specific') or {}).get('severity')
            if sev == 'CRITICAL':
                crit += 1
            elif sev == 'HIGH':
                high += 1
            elif sev in ('MODERATE', 'MEDIUM', 'LOW'):
                pass
            else:
                # No normalized severity label present (only CVSS vector, or
                # ecosystem without database_specific.severity). DECIDED
                # (QUESTIONS.pt-BR.md #6, 2026-09): fail-closed, treated as
                # HIGH — an unknown severity is not assumed safe.
                unscored += 1
status = 'FAIL' if (crit > 0 or high > 0 or unscored > 0) else 'PASS'
print(json.dumps({'status': status, 'critical': crit, 'high': high, 'unscored': unscored}))
")
else
  OSV_GATE='{"status":"SKIPPED","critical":0,"high":0,"unscored":0,"reason":"osv-scanner not installed"}'
fi
RESULT=$(echo "$RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
d['gates']['osv_scanner'] = json.loads('''$OSV_GATE''')
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
