#!/bin/bash
# Run mutation testing (Stryker Mutator) — validates test quality beyond
# coverage %. SLOW (re-runs the test suite once per surviving mutant
# candidate) — final gate only, never per-step or checkpoint.
#
# THRESHOLD DECIDED (QUESTIONS.pt-BR.md #3, 2026-09): stryker.conf.json now
# sets thresholds.break=50 — Stryker's own documented starting point when no
# historical baseline exists yet (below the low=60 mark, so a build that
# regresses meaningfully under an already-modest target fails immediately,
# without requiring a baseline measurement first). This is a starting
# guardrail, not a final number: once a real baseline mutation score is
# measured on an actual project, raise thresholds.break in
# stryker.conf.json to something closer to `low`/`high` — this script's
# PASS/FAIL reflects whatever is configured there automatically, no script
# change needed.
#
# Returns JSON, same shape as run-gates.sh.
set -euo pipefail
DIR="${1:-.}"
cd "$DIR"

RESULT='{"timestamp":"'$(date -Iseconds)'","gates":{},"overall":"PASS"}'

CONFIG="stryker.conf.json"
if [ ! -f "$CONFIG" ]; then
  RESULT=$(echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d['gates']['stryker']={'status':'SKIPPED','mutationScore':0,'reason':'no stryker.conf.json at project root (see templates/dev-quality/)'}
print(json.dumps(d,indent=2))
")
  echo "$RESULT"
  exit 0
fi

STRYKER_LOG=$(mktemp)
set +e
npx --yes stryker run --configFile "$CONFIG" >"$STRYKER_LOG" 2>&1
STRYKER_EXIT=$?
set -e

STRYKER_STATUS="PASS"
[ "$STRYKER_EXIT" -ne 0 ] && STRYKER_STATUS="FAIL"

# Parse the clear-text summary table's "All files" row, e.g.:
#   All files   |   85.00 |       34 |         0 |          4 |        2 |       0 |
MUTATION_SCORE=$(grep "All files" "$STRYKER_LOG" | head -1 | awk -F'|' '{gsub(/ /,"",$2); print $2}')
[ -z "${MUTATION_SCORE:-}" ] && MUTATION_SCORE=0
# Guard against non-numeric parse (e.g. log format changed)
case "$MUTATION_SCORE" in
  ''|*[!0-9.]*) MUTATION_SCORE=0 ;;
esac

rm -f "$STRYKER_LOG"

RESULT=$(echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d['gates']['stryker']={'status':'$STRYKER_STATUS','mutationScore':$MUTATION_SCORE}
print(json.dumps(d,indent=2))
")

echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d['gates'].values():
    if g['status']=='FAIL': d['overall']='FAIL'; break
print(json.dumps(d,indent=2))
"
