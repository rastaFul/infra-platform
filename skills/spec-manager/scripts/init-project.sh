#!/bin/bash
# Initialize .specs/ project structure
# Usage: init-project.sh <project-dir> <project-name> <description>
set -euo pipefail
DIR="${1:-.}"; NAME="${2:-$(basename "$DIR")}"; DESC="${3:-}"
SPECS="$DIR/.specs/project"
mkdir -p "$SPECS" "$DIR/.specs/audit" "$DIR/.specs/metrics" "$DIR/.specs/features"
TS=$(date -Iseconds)

[ ! -f "$SPECS/PROJECT.md" ] && cat > "$SPECS/PROJECT.md" << EOF
# $NAME
- **Description**: $DESC
- **Created**: $TS
- **Stack**: TypeScript, Node.js
- **Architecture**: Clean Architecture
EOF

[ ! -f "$SPECS/STATE.md" ] && cat > "$SPECS/STATE.md" << EOF
# State — $NAME
- **Status**: INITIALIZED
- **Last updated**: $TS
- **Current task**: none

## Tasks
(no tasks defined)
EOF

[ ! -f "$SPECS/DECISIONS.md" ] && cat > "$SPECS/DECISIONS.md" << EOF
# Decisions — $NAME

## Log
(no decisions recorded)
EOF

[ ! -f "$SPECS/ROADMAP.md" ] && cat > "$SPECS/ROADMAP.md" << EOF
# Roadmap — $NAME

## Milestones
(no milestones defined)
EOF

echo "✅ .specs/ initialized for $NAME"
