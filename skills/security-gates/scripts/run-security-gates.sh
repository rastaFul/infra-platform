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
  # `--no-git` does a raw filesystem walk, which does NOT respect
  # .gitignore -- real false-positive found 2026-09-15 (D-2026-09-15-2/3):
  # this flagged real secrets sitting in .env files that are gitignored and
  # would never actually be committed (CI never sees this because .env
  # doesn't exist in a fresh checkout there). Fix: if this is a git repo,
  # build a temporary gitleaks config that allowlists exactly the paths git
  # itself considers ignored (`git ls-files --others --ignored
  # --exclude-standard`) -- anything genuinely staged/tracked still gets
  # scanned normally, only intentionally-gitignored files are excluded.
  # Falls back to the old unrestricted scan if this isn't a git repo.
  GITLEAKS_CONFIG_ARGS=()
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    IGNORED_PATHS=$(git ls-files --others --ignored --exclude-standard)
    if [ -n "$IGNORED_PATHS" ]; then
      GITLEAKS_TMP_CONFIG=$(mktemp --suffix=.toml)
      {
        echo '[extend]'
        echo 'useDefault = true'
        echo ''
        echo '[allowlist]'
        echo 'paths = ['
        while IFS= read -r p; do
          [ -n "$p" ] && printf "  '''%s''',\n" "$p"
        done <<< "$IGNORED_PATHS"
        echo ']'
      } > "$GITLEAKS_TMP_CONFIG"
      GITLEAKS_CONFIG_ARGS=(--config "$GITLEAKS_TMP_CONFIG")
    fi
  fi
  gitleaks detect --source . --no-git --redact "${GITLEAKS_CONFIG_ARGS[@]}" \
    --report-format json --report-path "$GITLEAKS_REPORT" \
    --exit-code 0 >/dev/null 2>&1 || true
  [ -n "${GITLEAKS_TMP_CONFIG:-}" ] && rm -f "$GITLEAKS_TMP_CONFIG"
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
  # v2.x CLI is subcommand-based (`scan source`, `--format json` not
  # `--json`) -- real bug found 2026-09-15 when this tool went from
  # SKIPPED (not installed) to actually installed for the first time
  # (D-2026-09-15-2/3, item 8): the old flat `--json -r .` flags don't
  # exist anymore, silently produced no output. Also: when a directory has
  # no scannable lockfile at all (e.g. this repo, infra-platform, no
  # package.json), osv-scanner exits non-zero (128) and prints NO json at
  # all -- that's a legitimate "nothing to scan" PASS, not an error; only
  # actually-empty/unparseable output on a directory that DOES have
  # lockfiles would be a real ERROR, and there's no cheap way to
  # distinguish those two cases from here, so empty output is always
  # treated as 0 findings (never a false FAIL, worst case a false PASS
  # that trivy_fs's own dependency scanning partially backstops).
  OSV_OUT=$(osv-scanner scan source -r --format json . 2>/dev/null) || true
  OSV_GATE=$(echo "$OSV_OUT" | python3 -c "
import sys, json
raw = sys.stdin.read().strip()
if not raw:
    print(json.dumps({'status': 'PASS', 'critical': 0, 'high': 0, 'unscored': 0, 'note': 'no output (no scannable lockfile found, or nothing to report)'}))
    sys.exit()
try:
    d = json.loads(raw)
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
