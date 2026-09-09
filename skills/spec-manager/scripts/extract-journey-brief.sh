#!/bin/bash
# Extract the evaluator-safe brief from journey.md — strips Happy Path
# (and any section not on the whitelist) so implementation hints can't
# leak into the ux-journey-judge prompt.
# Usage: extract-journey-brief.sh <project-dir> <feature-name>
set -euo pipefail
DIR="${1:-.}"; FEATURE="${2:-unnamed}"
SLUG=$(echo "$FEATURE" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
JOURNEY="$DIR/.specs/features/$SLUG/journey.md"

if [ ! -f "$JOURNEY" ]; then
  echo "❌ journey.md not found at $JOURNEY" >&2
  exit 1
fi

python3 -c "
import re

WHITELIST = ['Actor', 'Goal', 'Starting State', 'Entry Points',
             'Success Criteria', 'Failure Paths', 'Recovery Expectations',
             'Friction Budget', 'Hard Failure Notes']

text = open('$JOURNEY').read()
sections = re.split(r'^## ', text, flags=re.M)[1:]  # drop preamble before first ##
out = []
for sec in sections:
    lines = sec.split('\n', 1)
    heading = lines[0].strip()
    body = lines[1] if len(lines) > 1 else ''
    if heading in WHITELIST:
        out.append(f'## {heading}\n{body.rstrip()}')

print('# UX Journey Brief — evaluator-safe excerpt')
print('# (Happy Path and any non-whitelisted section removed)')
print()
print('\n\n'.join(out))
"
