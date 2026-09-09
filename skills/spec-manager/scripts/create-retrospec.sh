#!/bin/bash
# Create retrospec for quick mode executions
# Usage: create-retrospec.sh <project-dir> <feature-name> <description> <files-changed> <decisions>
set -euo pipefail
DIR="${1:-.}"; FEATURE="${2:-unnamed}"; DESC="${3:-}"; FILES="${4:-none}"; DECISIONS="${5:-none}"
SLUG=$(echo "$FEATURE" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
SPEC_DIR="$DIR/.specs/features/$SLUG"
mkdir -p "$SPEC_DIR"
TS=$(date -Iseconds)

cat > "$SPEC_DIR/spec-retro.md" << EOF
# Spec Retroativa: $FEATURE
- **Mode**: Quick mode (requested by user)
- **Data**: $TS
- **O que foi feito**: $DESC
- **Arquivos modificados**: $FILES
- **Decisions made**: $DECISIONS
- **Risks**: Execution without prior spec — review decisions
EOF

echo "✅ Retrospec created at $SPEC_DIR/spec-retro.md"
