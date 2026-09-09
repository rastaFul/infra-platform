#!/bin/bash
# Create metrics file in .specs/metrics/
# Usage: log-metrics.sh <project-dir> <task-name> <duration> <gates-json> <result>
set -euo pipefail
DIR="${1:-.}"; TASK_NAME="${2:-unnamed}"; DURATION="${3:-0s}"; GATES_JSON="${4:-{}}"; RESULT="${5:-UNKNOWN}"
METRICS_DIR="$DIR/.specs/metrics"
mkdir -p "$METRICS_DIR"
TS=$(date +%Y%m%d-%H%M%S)
SLUG=$(echo "$TASK_NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
FILE="$METRICS_DIR/${TS}-${SLUG}.md"

python3 -c "
import json
gates = json.loads('$GATES_JSON')
g = gates.get('gates', {})
lines = []
lines.append(f'# Metrics: $TASK_NAME')
lines.append(f'- **Date**: $(date -Iseconds)')
lines.append(f'- **Agent**: harness')
lines.append(f'- **Task**: $TASK_NAME')
lines.append(f'- **Duration**: $DURATION')
lines.append(f'- **Gates**: passed={sum(1 for v in g.values() if v[\"status\"]==\"PASS\")} failed={sum(1 for v in g.values() if v[\"status\"]==\"FAIL\")}')
lines.append(f'- **Result**: $RESULT')
lines.append('')
if 'jest' in g:
    lines.append('## Code Quality')
    j = g.get('jest', {})
    lines.append(f'- **tests**: {j.get(\"passed\",0)}/{j.get(\"total\",0)} passed')
if 'coverage' in g:
    c = g.get('coverage', {})
    lines.append(f'- **coverage**: {c.get(\"statements\",0)}% stmts, {c.get(\"branches\",0)}% branches')
if 'sonar' in g and g['sonar']['status'] != 'SKIPPED':
    s = g['sonar']
    lines.append(f'- **sonar**: gate={s[\"status\"]}, bugs={s.get(\"bugs\",0)}, vulns={s.get(\"vulnerabilities\",0)}, smells={s.get(\"smells\",0)}')
lines.append('')
print('\n'.join(lines))
" > "$FILE"
echo "✅ Metrics saved to $FILE"
