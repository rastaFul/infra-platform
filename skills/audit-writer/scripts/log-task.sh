#!/bin/bash
# Log task result to .specs/audit/execution.md
# Usage: log-task.sh <project-dir> <task-number> <task-name> <gates-json>
set -euo pipefail
DIR="${1:-.}"; TASK_NUM="${2:-0}"; TASK_NAME="${3:-unnamed}"; GATES_JSON="${4:-{}}"
AUDIT_FILE="$DIR/.specs/audit/execution.md"
mkdir -p "$(dirname "$AUDIT_FILE")"
TS=$(date -Iseconds)

python3 -c "
import json
gates = json.loads('$GATES_JSON')
lines = []
lines.append(f'## Task $TASK_NUM: $TASK_NAME — $TS')
for name, g in gates.get('gates', {}).items():
    status = g.get('status', '?')
    detail = ''
    if name == 'eslint': detail = f' ({g.get(\"errors\",0)} errors, {g.get(\"warnings\",0)} warnings)'
    elif name == 'jest': detail = f' ({g.get(\"passed\",0)}/{g.get(\"total\",0)} tests)'
    elif name == 'coverage': detail = f' ({g.get(\"statements\",0)}% stmts, {g.get(\"branches\",0)}% branches)'
    elif name == 'audit': detail = f' ({g.get(\"critical\",0)} critical, {g.get(\"high\",0)} high)'
    elif name == 'sonar' and status != 'SKIPPED': detail = f' (bugs:{g.get(\"bugs\",0)}, vulns:{g.get(\"vulnerabilities\",0)}, smells:{g.get(\"smells\",0)})'
    lines.append(f'- {name}: {status}{detail}')
lines.append(f'- Status: {\"DONE\" if gates.get(\"overall\")==\"PASS\" else \"FAILED\"}')
lines.append('')
print('\n'.join(lines))
" >> "$AUDIT_FILE"
echo "✅ Task $TASK_NUM logged to $AUDIT_FILE"
