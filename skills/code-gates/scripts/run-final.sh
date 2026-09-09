#!/bin/bash
# Run ALL gates: tsc, eslint, jest, coverage, audit, sonar, architecture
# conformance, duplication/complexity, mutation testing. Returns JSON.
#
# DECIDED (QUESTIONS.pt-BR.md #19, 2026-09): wires in the 3 dev-quality
# scripts that existed standalone but were never called from here
# (run-architecture-gate.sh, run-quality-extra.sh, run-mutation.sh) — closes
# the "written but orphaned" gap flagged in QUESTIONS.md. Mutation testing
# (Stryker) is slow by design (re-runs the suite per surviving mutant) —
# still run here rather than per-task, since this script itself is already
# the "WHEN FINISHING all tasks" final gate, not the per-task one.
set -euo pipefail
DIR="${1:-.}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CODE_GATES_SCRIPTS="$SKILL_DIR/scripts"

# Run step gates + checkpoint gates
STEP=$(bash "$SKILL_DIR/scripts/run-gates.sh" "$DIR" 2>/dev/null)
CHECKPOINT=$(bash "$SKILL_DIR/scripts/run-checkpoint.sh" "$DIR" 2>/dev/null)
ARCHITECTURE=$(bash "$CODE_GATES_SCRIPTS/run-architecture-gate.sh" "$DIR" 2>/dev/null)
QUALITY_EXTRA=$(bash "$CODE_GATES_SCRIPTS/run-quality-extra.sh" "$DIR" 2>/dev/null)
MUTATION=$(bash "$CODE_GATES_SCRIPTS/run-mutation.sh" "$DIR" 2>/dev/null)

# Merge results
RESULT=$(python3 -c "
import json, sys
step = json.loads('''$STEP''')
checkpoint = json.loads('''$CHECKPOINT''')
architecture = json.loads('''$ARCHITECTURE''')
quality_extra = json.loads('''$QUALITY_EXTRA''')
mutation = json.loads('''$MUTATION''')
merged = step
merged['gates'].update(checkpoint['gates'])
merged['gates'].update(architecture['gates'])
merged['gates'].update(quality_extra['gates'])
merged['gates'].update(mutation['gates'])

# Sonar
sonar = {'status': 'SKIPPED', 'bugs': 0, 'vulnerabilities': 0, 'smells': 0, 'coverage': 0, 'duplications': 0}
merged['gates']['sonar'] = sonar
merged['overall'] = 'PASS'
for g in merged['gates'].values():
    if g['status'] == 'FAIL':
        merged['overall'] = 'FAIL'
        break
print(json.dumps(merged, indent=2))
")

# Try sonar if available
if command -v sonar-scan &>/dev/null && [ -n "${SONAR_HOST_URL:-}" ]; then
  SONAR_OUT=$(sonar-scan "$DIR" 2>&1) || true
  # Same unprotected-grep class of bug as run-gates.sh/run-mutation.sh —
  # fixed proactively here too (not actively triggered by any of today's
  # failures, since this whole block only runs with a real sonar-scan +
  # SONAR_HOST_URL configured, which none of the rollout targets have —
  # but the same crash would hit the moment someone does).
  SONAR_GATE=$(echo "$SONAR_OUT" | grep "SONAR_GATE=" | cut -d= -f2 || true)
  [ -z "$SONAR_GATE" ] && SONAR_GATE="SKIPPED"
  SONAR_BUGS=$(echo "$SONAR_OUT" | grep "bugs:" | awk '{print $2}' || echo 0)
  SONAR_VULNS=$(echo "$SONAR_OUT" | grep "vulnerabilities:" | awk '{print $2}' || echo 0)
  SONAR_SMELLS=$(echo "$SONAR_OUT" | grep "code_smells:" | awk '{print $2}' || echo 0)
  SONAR_COV=$(echo "$SONAR_OUT" | grep "coverage:" | awk '{print $2}' || echo 0)
  SONAR_DUP=$(echo "$SONAR_OUT" | grep "duplicated_lines_density:" | awk '{print $2}' || echo 0)
  [ -z "$SONAR_BUGS" ] && SONAR_BUGS=0
  [ -z "$SONAR_VULNS" ] && SONAR_VULNS=0
  [ -z "$SONAR_SMELLS" ] && SONAR_SMELLS=0
  [ -z "$SONAR_COV" ] && SONAR_COV=0
  [ -z "$SONAR_DUP" ] && SONAR_DUP=0
  RESULT=$(echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d['gates']['sonar']={'status':'${SONAR_GATE:-SKIPPED}','bugs':${SONAR_BUGS:-0},'vulnerabilities':${SONAR_VULNS:-0},'smells':${SONAR_SMELLS:-0},'coverage':${SONAR_COV:-0},'duplications':${SONAR_DUP:-0}}
if d['gates']['sonar']['status']=='FAIL': d['overall']='FAIL'
print(json.dumps(d,indent=2))
")
fi

echo "$RESULT"
