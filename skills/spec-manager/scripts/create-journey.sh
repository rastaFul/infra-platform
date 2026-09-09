#!/bin/bash
# Create UX journey definition from template
# Usage: create-journey.sh <project-dir> <feature-name> <goal>
set -euo pipefail
DIR="${1:-.}"; FEATURE="${2:-unnamed}"; GOAL="${3:-}"
SLUG=$(echo "$FEATURE" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
SPEC_DIR="$DIR/.specs/features/$SLUG"
mkdir -p "$SPEC_DIR/screenshots/ux"
TS=$(date -Iseconds)

[ ! -f "$SPEC_DIR/journey.md" ] && cat > "$SPEC_DIR/journey.md" << EOF
# UX Journey: $FEATURE
- **Created**: $TS
- **Status**: DRAFT

## Actor
(who is the user — role, auth state, prior familiarity)

## Goal
$GOAL

## Starting State
(what's true before the journey starts — auth, existing data, prior actions)

## Entry Points
(valid starting URLs/screens — not instructions)
-

## Success Criteria
(observable, not adjectives — each must be independently verifiable)
-

## Happy Path
(internal reference only — task-executor and human reviewers may read this;
NEVER shown to ux-journey-judge, stripped by extract-journey-brief.sh)
-

## Failure Paths
(scenarios relevant to this goal — not exhaustive, pick what matters)
-

## Recovery Expectations
(how the user should be able to recover from the failure paths above)
-

## Friction Budget
- wrong_actions: 1
- backtracks: 1
- dead_ends: 0

## Hard Failure Notes
(journey-specific additions to the standard hard-failure list, if any)
- none
EOF

echo "✅ Journey created at $SPEC_DIR/journey.md"
