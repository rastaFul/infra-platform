#!/bin/bash
# Run architecture-conformance gate: dependency-cruiser enforces the layering
# rules from steering/architecture.md and steering/service-layers.md (domain
# has zero external deps, application never imports infrastructure, handlers
# never touch repositories directly, etc). Ruleset lives in
# .dependency-cruiser.cjs (copied from templates/dev-quality/ by install.sh).
# Returns JSON, same shape as run-gates.sh.
set -euo pipefail
DIR="${1:-.}"
SRC="${2:-src}"
cd "$DIR"

RESULT='{"timestamp":"'$(date -Iseconds)'","gates":{},"overall":"PASS"}'

CONFIG=".dependency-cruiser.cjs"

if [ ! -f "$CONFIG" ]; then
  RESULT=$(echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d['gates']['depcruise']={'status':'SKIPPED','errors':0,'warnings':0,'reason':'no .dependency-cruiser.cjs at project root (see templates/dev-quality/)'}
print(json.dumps(d,indent=2))
")
  echo "$RESULT"
  exit 0
fi

if [ ! -d "$SRC" ]; then
  RESULT=$(echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d['gates']['depcruise']={'status':'SKIPPED','errors':0,'warnings':0,'reason':'no $SRC/ directory found'}
print(json.dumps(d,indent=2))
")
  echo "$RESULT"
  exit 0
fi

DEPCRUISE_OUT=$(npx --yes dependency-cruiser --config "$CONFIG" --output-type json "$SRC" 2>/dev/null) && DEPCRUISE_RUN_OK=1 || DEPCRUISE_RUN_OK=0

DEPCRUISE_ERRORS=$(echo "$DEPCRUISE_OUT" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('summary',{}).get('error',0))
except Exception:
    print(0)
" 2>/dev/null || echo 0)
DEPCRUISE_WARN=$(echo "$DEPCRUISE_OUT" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('summary',{}).get('warn',0))
except Exception:
    print(0)
" 2>/dev/null || echo 0)
[ -z "$DEPCRUISE_ERRORS" ] && DEPCRUISE_ERRORS=0
[ -z "$DEPCRUISE_WARN" ] && DEPCRUISE_WARN=0

# dependency-cruiser exits non-zero when any "error"-severity rule is violated
# (matches how we treat the "NEVER"/"ZERO" rules from the steering docs).
DEPCRUISE_STATUS="PASS"
[ "$DEPCRUISE_RUN_OK" -eq 0 ] && DEPCRUISE_STATUS="FAIL"
[ "$DEPCRUISE_ERRORS" -gt 0 ] 2>/dev/null && DEPCRUISE_STATUS="FAIL" || true

RESULT=$(echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d['gates']['depcruise']={'status':'$DEPCRUISE_STATUS','errors':$DEPCRUISE_ERRORS,'warnings':$DEPCRUISE_WARN}
print(json.dumps(d,indent=2))
")

echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d['gates'].values():
    if g['status']=='FAIL': d['overall']='FAIL'; break
print(json.dumps(d,indent=2))
"
