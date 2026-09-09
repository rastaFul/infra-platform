#!/bin/bash
# Run checkpoint gates: coverage, npm audit. Returns JSON.
set -euo pipefail
DIR="${1:-.}"
cd "$DIR"

RESULT='{"timestamp":"'$(date -Iseconds)'","gates":{},"overall":"PASS"}'

# coverage
COV_OUT=$(npm run test:coverage -- --json --silent 2>/dev/null || npx jest --coverage --json --silent 2>/dev/null) && COV_STATUS="PASS" || COV_STATUS="FAIL"
COV_STMTS=$(echo "$COV_OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);t=d.get('coverageMap',{});s=d.get('numTotalTests',0);print(0)" 2>/dev/null || echo 0)
# Parse from text output as fallback
COV_TEXT=$(npm run test:coverage 2>&1 | grep "All files" || echo "")
COV_STMTS=$(echo "$COV_TEXT" | awk '{print $4}' | tr -d '%' 2>/dev/null || echo 0)
COV_BRANCH=$(echo "$COV_TEXT" | awk '{print $6}' | tr -d '%' 2>/dev/null || echo 0)
[ -z "$COV_STMTS" ] && COV_STMTS=0
[ -z "$COV_BRANCH" ] && COV_BRANCH=0
RESULT=$(echo "$RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);d['gates']['coverage']={'status':'$COV_STATUS','statements':$COV_STMTS,'branches':$COV_BRANCH};print(json.dumps(d))")

# npm audit
AUDIT_OUT=$(npm audit --json 2>/dev/null) || true
AUDIT_CRIT=$(echo "$AUDIT_OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);v=d.get('metadata',{}).get('vulnerabilities',{});print(v.get('critical',0))" 2>/dev/null || echo 0)
AUDIT_HIGH=$(echo "$AUDIT_OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);v=d.get('metadata',{}).get('vulnerabilities',{});print(v.get('high',0))" 2>/dev/null || echo 0)
AUDIT_STATUS="PASS"
[ "$AUDIT_CRIT" -gt 0 ] || [ "$AUDIT_HIGH" -gt 0 ] && AUDIT_STATUS="FAIL"
RESULT=$(echo "$RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);d['gates']['audit']={'status':'$AUDIT_STATUS','critical':$AUDIT_CRIT,'high':$AUDIT_HIGH};print(json.dumps(d))")

echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d['gates'].values():
    if g['status']=='FAIL': d['overall']='FAIL'; break
print(json.dumps(d,indent=2))
"
