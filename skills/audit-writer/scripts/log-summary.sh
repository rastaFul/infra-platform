#!/bin/bash
# Log execution summary to .specs/audit/execution.md
# Usage: log-summary.sh <project-dir> <total> <done> <failed> <gates-json> <files-changed>
set -euo pipefail
DIR="${1:-.}"; TOTAL="${2:-0}"; DONE="${3:-0}"; FAILED="${4:-0}"; GATES_JSON="${5:-{}}"; FILES="${6:-none}"
AUDIT_FILE="$DIR/.specs/audit/execution.md"
mkdir -p "$(dirname "$AUDIT_FILE")"
TS=$(date -Iseconds)

python3 -c "
import json
gates = json.loads('$GATES_JSON')
lines = []
lines.append(f'## Execution Summary — $TS')
lines.append(f'- Tasks: $TOTAL total, $DONE done, $FAILED failed')
gate_list = ', '.join(f'{k}={v[\"status\"]}' for k,v in gates.get('gates',{}).items())
lines.append(f'- Gates: {gate_list}')
lines.append(f'- Files changed: $FILES')
lines.append('')
print('\n'.join(lines))
" >> "$AUDIT_FILE"
echo "✅ Summary logged to $AUDIT_FILE"
