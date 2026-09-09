#!/bin/bash
# Register a ux-journey-judge result: execution.md entry + metrics file
# Usage: log-ux-result.sh <project-dir> <feature-name> <result-json>
set -euo pipefail
DIR="${1:-.}"; FEATURE="${2:-unnamed}"; RESULT_JSON="${3:-}"
[ -z "$RESULT_JSON" ] && RESULT_JSON='{}'
SLUG=$(echo "$FEATURE" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
AUDIT_FILE="$DIR/.specs/audit/execution.md"
METRICS_DIR="$DIR/.specs/metrics"
mkdir -p "$(dirname "$AUDIT_FILE")" "$METRICS_DIR"
TS=$(date -Iseconds)
TS_COMPACT=$(date +%Y%m%d-%H%M%S)

python3 -c "
import json
r = json.loads('''$RESULT_JSON''')
status = r.get('status', 'UNKNOWN')
gc = r.get('goal_completion', 0)
hard = r.get('hard_failures', [])
m = r.get('metrics', {})
fb_exceeded = r.get('friction_budget_exceeded', False)
score = r.get('score', 'n/a')

# --- audit entry ---
lines = []
lines.append(f'## UX Journey: $FEATURE — $TS')
lines.append(f'- ux-journey-judge: {status} (goal_completion={gc}, friction_budget_exceeded={fb_exceeded})')
lines.append(f'- metrics: wrong_actions={m.get(\"wrong_actions\",0)} backtracks={m.get(\"backtracks\",0)} dead_ends={m.get(\"dead_ends\",0)} failed_actions={m.get(\"failed_actions\",0)} steps_taken={m.get(\"steps_taken\",0)}')
if hard:
    lines.append(f'- hard_failures: {\"; \".join(hard)}')
lines.append(f'- Status: {\"DONE\" if status==\"PASS\" else \"FAILED\" if status==\"FAIL\" else \"BLOCKED\"}')
lines.append('')
with open('$AUDIT_FILE', 'a') as f:
    f.write('\n'.join(lines) + '\n')

# --- metrics file ---
mlines = []
mlines.append(f'# UX Metrics: $FEATURE')
mlines.append(f'- **Date**: $TS')
mlines.append(f'- **Agent**: harness-dev / ux-journey-judge')
mlines.append(f'- **Status**: {status}')
mlines.append(f'- **Goal completion**: {gc}')
mlines.append(f'- **Score (diagnostic)**: {score}')
mlines.append(f'- **Friction budget exceeded**: {fb_exceeded}')
mlines.append(f'- **Hard failures**: {hard if hard else \"none\"}')
mlines.append('')
mlines.append('## Metrics')
for k, v in m.items():
    mlines.append(f'- {k}: {v}')
mlines.append('')
mlines.append('## Findings')
for finding in r.get('findings', []):
    mlines.append(f'- [{finding.get(\"severity\",\"?\")}] {finding.get(\"description\",\"\")}')
print('\n'.join(mlines))
" > "$METRICS_DIR/${TS_COMPACT}-${SLUG}.ux.md"

echo "✅ UX result logged: execution.md + $METRICS_DIR/${TS_COMPACT}-${SLUG}.ux.md"
