#!/bin/bash
# Run per-step gates: tsc, eslint, jest. Returns JSON.
set -euo pipefail
DIR="${1:-.}"
cd "$DIR"

RESULT='{"timestamp":"'$(date -Iseconds)'","gates":{},"overall":"PASS"}'

# tsc
# BUG FOUND AND FIXED via a real product-repo rollout (artists-booking,
# 2026-09-08): `grep -c PATTERN || echo 0` is broken — `grep -c` ALWAYS
# prints a valid count to stdout (including "0"), but its own exit code is
# 1 whenever the count is zero (not an error, just "no matches" — the
# NORMAL/GOOD case here, zero tsc errors). So on a clean run, this used to
# both print grep's own "0" AND trigger the `|| echo 0` fallback, producing
# the literal two-line string "0\n0" instead of "0" — which broke the
# python3 JSON embed downstream (`'errors':0\n0` is invalid syntax) and,
# under `set -e` in the CALLING script (run-final.sh), silently crashed
# the entire gate chain with zero output. Fixed: `|| true` (adds nothing)
# instead of `|| echo 0` (which duplicates), plus an explicit empty-string
# guard for the genuine-hard-error case where grep prints nothing at all.
TSC_OUT=$(npx tsc --noEmit 2>&1) && TSC_STATUS="PASS" || TSC_STATUS="FAIL"
TSC_ERRORS=$(echo "$TSC_OUT" | grep -c "error TS" 2>/dev/null || true)
[ -z "$TSC_ERRORS" ] && TSC_ERRORS=0
RESULT=$(echo "$RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);d['gates']['tsc']={'status':'$TSC_STATUS','errors':$TSC_ERRORS};print(json.dumps(d))")

# eslint
LINT_OUT=$(npm run lint 2>&1) && LINT_STATUS="PASS" || LINT_STATUS="FAIL"
LINT_ERRORS=$(echo "$LINT_OUT" | grep -oP '\d+ error' | grep -oP '\d+' | head -1 || echo 0)
LINT_WARNINGS=$(echo "$LINT_OUT" | grep -oP '\d+ warning' | grep -oP '\d+' | head -1 || echo 0)
[ -z "$LINT_ERRORS" ] && LINT_ERRORS=0
[ -z "$LINT_WARNINGS" ] && LINT_WARNINGS=0
RESULT=$(echo "$RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);d['gates']['eslint']={'status':'$LINT_STATUS','errors':$LINT_ERRORS,'warnings':$LINT_WARNINGS};print(json.dumps(d))")

# jest
TEST_OUT=$(npm test -- --json --silent 2>/dev/null) && TEST_STATUS="PASS" || TEST_STATUS="FAIL"
TEST_TOTAL=$(echo "$TEST_OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('numTotalTests',0))" 2>/dev/null || echo 0)
TEST_PASSED=$(echo "$TEST_OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('numPassedTests',0))" 2>/dev/null || echo 0)
TEST_FAILED=$(echo "$TEST_OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('numFailedTests',0))" 2>/dev/null || echo 0)
RESULT=$(echo "$RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);d['gates']['jest']={'status':'$TEST_STATUS','total':$TEST_TOTAL,'passed':$TEST_PASSED,'failed':$TEST_FAILED};print(json.dumps(d))")

# Overall
OVERALL="PASS"
echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d['gates'].values():
    if g['status']=='FAIL': d['overall']='FAIL'; break
print(json.dumps(d,indent=2))
"
