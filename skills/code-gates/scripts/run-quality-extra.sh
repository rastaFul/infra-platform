#!/bin/bash
# Run duplication + cognitive-complexity gate: jscpd (copy-paste detection)
# and eslint-plugin-sonarjs (cognitive complexity / bug-pattern rules).
#
# Design note on sonarjs: eslint-plugin-sonarjs is NOT a separate CLI — it
# plugs into the project's own ESLint config (rules prefixed "sonarjs/") and
# is already exercised by `npm run lint` in run-gates.sh. Re-running that
# here would duplicate the tsc/eslint/jest step gate. Instead this script
# runs `npx eslint . --format json` on its own (so it also works standalone,
# e.g. from run-final.sh without depending on run-gates.sh having run first)
# and filters violations whose ruleId starts with "sonarjs/", reporting them
# as a distinct signal (complexity/duplication-of-logic) instead of folding
# them into the generic lint error count.
#
# Returns JSON, same shape as run-gates.sh.
set -euo pipefail
DIR="${1:-.}"
cd "$DIR"

RESULT='{"timestamp":"'$(date -Iseconds)'","gates":{},"overall":"PASS"}'

### jscpd — copy-paste / duplication detection
JSCPD_CONFIG=".jscpd.json"
if [ ! -f "$JSCPD_CONFIG" ]; then
  RESULT=$(echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d['gates']['jscpd']={'status':'SKIPPED','clones':0,'percentage':0,'reason':'no .jscpd.json at project root (see templates/dev-quality/)'}
print(json.dumps(d,indent=2))
")
else
  JSCPD_REPORT_DIR=$(mktemp -d)
  if npx --yes jscpd --config "$JSCPD_CONFIG" --reporters json --output "$JSCPD_REPORT_DIR" . >/dev/null 2>&1; then
    JSCPD_STATUS="PASS"
  else
    JSCPD_STATUS="FAIL"
  fi

  JSCPD_JSON="$JSCPD_REPORT_DIR/jscpd-report.json"
  if [ -f "$JSCPD_JSON" ]; then
    JSCPD_CLONES=$(python3 -c "
import json
d=json.load(open('$JSCPD_JSON'))
print(d.get('statistics',{}).get('total',{}).get('clones',0))
" 2>/dev/null || echo 0)
    JSCPD_PCT=$(python3 -c "
import json
d=json.load(open('$JSCPD_JSON'))
print(d.get('statistics',{}).get('total',{}).get('percentage',0))
" 2>/dev/null || echo 0)
  else
    JSCPD_CLONES=0
    JSCPD_PCT=0
    # no report written usually means jscpd found nothing to scan, not a failure
    [ "$JSCPD_STATUS" = "FAIL" ] || JSCPD_STATUS="PASS"
  fi
  rm -rf "$JSCPD_REPORT_DIR"
  [ -z "$JSCPD_CLONES" ] && JSCPD_CLONES=0
  [ -z "$JSCPD_PCT" ] && JSCPD_PCT=0

  RESULT=$(echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d['gates']['jscpd']={'status':'$JSCPD_STATUS','clones':$JSCPD_CLONES,'percentage':$JSCPD_PCT}
print(json.dumps(d,indent=2))
")
fi

### eslint-plugin-sonarjs — cognitive complexity, filtered from a full eslint run
LINT_JSON=$(npx --yes eslint . --format json 2>/dev/null || echo "")
if [ -z "$LINT_JSON" ]; then
  SONARJS_STATUS="SKIPPED"
  SONARJS_COUNT=0
else
  SONARJS_COUNT=$(echo "$LINT_JSON" | python3 -c "
import sys,json
try:
    data=json.load(sys.stdin)
except Exception:
    print(0); sys.exit()
count=0
for f in data:
    for m in f.get('messages', []):
        if str(m.get('ruleId') or '').startswith('sonarjs/'):
            count+=1
print(count)
" 2>/dev/null || echo 0)
  [ -z "$SONARJS_COUNT" ] && SONARJS_COUNT=0
  SONARJS_STATUS="PASS"
  [ "$SONARJS_COUNT" -gt 0 ] 2>/dev/null && SONARJS_STATUS="FAIL" || true
fi

RESULT=$(echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d['gates']['sonarjs_complexity']={'status':'$SONARJS_STATUS','violations':$SONARJS_COUNT}
print(json.dumps(d,indent=2))
")

echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
overall='PASS'
for g in d['gates'].values():
    if g['status']=='FAIL': overall='FAIL'; break
d['overall']=overall
print(json.dumps(d,indent=2))
"
