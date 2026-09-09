#!/bin/bash
# Log doc update to .specs/audit/execution.md
# Usage: log-doc-update.sh <project-dir> <branch> <files> <reason>
set -euo pipefail
DIR="${1:-.}"; BRANCH="${2:-unknown}"; FILES="${3:-none}"; REASON="${4:-unspecified}"
AUDIT_FILE="$DIR/.specs/audit/execution.md"
mkdir -p "$(dirname "$AUDIT_FILE")"
TS=$(date -Iseconds)

cat >> "$AUDIT_FILE" << EOF

## $TS DOC_UPDATE
- **Branch**: $BRANCH
- **Files changed**: $FILES
- **Reason**: $REASON

EOF
echo "✅ Doc update logged to $AUDIT_FILE"
