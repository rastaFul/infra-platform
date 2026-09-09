#!/bin/bash
# Update STATE.md
# Usage: update-state.sh <project-dir> <status> [task-name] [task-status]
set -euo pipefail
DIR="${1:-.}"; STATUS="${2:-UNKNOWN}"; TASK_NAME="${3:-}"; TASK_STATUS="${4:-}"
STATE_FILE="$DIR/.specs/project/STATE.md"
TS=$(date -Iseconds)

if [ ! -f "$STATE_FILE" ]; then
  echo "❌ STATE.md not found at $STATE_FILE"
  exit 1
fi

# Update status and timestamp
sed -i "s/^- \*\*Status\*\*:.*/- **Status**: $STATUS/" "$STATE_FILE"
sed -i "s/^- \*\*Last updated\*\*:.*/- **Last updated**: $TS/" "$STATE_FILE"

if [ -n "$TASK_NAME" ] && [ -n "$TASK_STATUS" ]; then
  sed -i "s/^- \*\*Current task\*\*:.*/- **Current task**: $TASK_NAME ($TASK_STATUS)/" "$STATE_FILE"
fi

echo "✅ STATE.md updated: status=$STATUS"
