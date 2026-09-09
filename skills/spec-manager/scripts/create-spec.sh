#!/bin/bash
# Create feature spec from template
# Usage: create-spec.sh <project-dir> <feature-name> <description>
set -euo pipefail
DIR="${1:-.}"; FEATURE="${2:-unnamed}"; DESC="${3:-}"
SLUG=$(echo "$FEATURE" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
SPEC_DIR="$DIR/.specs/features/$SLUG"
mkdir -p "$SPEC_DIR"
TS=$(date -Iseconds)

[ ! -f "$SPEC_DIR/spec.md" ] && cat > "$SPEC_DIR/spec.md" << EOF
# Spec: $FEATURE
- **Created**: $TS
- **Status**: DRAFT

## Objetivo
$DESC

## Contexto
(describe business context)

## Tasks
- [ ] Task 1: (definir)

## Done When
- [ ] (completion criterion)

## Constraints
- TDD mandatory
- Gates must pass (tsc, eslint, jest)
- Coverage ≥80% in use cases

## Out of Scope
(what is NOT part of this spec)
EOF

echo "✅ Spec created at $SPEC_DIR/spec.md"
