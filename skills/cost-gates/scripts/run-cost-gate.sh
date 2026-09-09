#!/bin/bash
# Runs Infracost against a Terraform directory. THRESHOLD DECIDED
# (QUESTIONS.pt-BR.md #1, 2026-09): baseline infra cost is $0 (local-only
# platform stack). Any nonzero monthly cost is an increase over that
# baseline and blocks — "any value" per the user's own answer. Once real
# cloud spend is deliberately provisioned (first paid resource approved via
# its own spec), this should switch to a true diff-based gate
# (`infracost diff --compare-to <stored-baseline>.json`) so the bar becomes
# "any INCREASE over the new nonzero baseline", not "any cost at all" —
# tracked as a follow-up, not done here since there is no real baseline to
# diff against yet.
set -euo pipefail

DIR="${1:-.}"
RESULT='{"timestamp":"'"$(date -Iseconds)"'","gates":{},"overall":"PASS"}'

if ! command -v infracost &>/dev/null; then
  echo '{"timestamp":"'"$(date -Iseconds)"'","gates":{"infracost":{"status":"SKIPPED","reason":"infracost not installed"}},"overall":"SKIPPED"}'
  exit 0
fi

if [ -z "${INFRACOST_API_KEY:-}" ]; then
  echo '{"timestamp":"'"$(date -Iseconds)"'","gates":{"infracost":{"status":"SKIPPED","reason":"INFRACOST_API_KEY not set — see docs/runbooks/infracost-api-key.md"}},"overall":"SKIPPED"}'
  exit 0
fi

COST_JSON=$(infracost breakdown --path "$DIR" --format json 2>/dev/null || echo '{}')
MONTHLY=$(echo "$COST_JSON" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('totalMonthlyCost','0'))" 2>/dev/null || echo "0")

python3 -c "
import json
d = json.loads('$RESULT')
monthly = float('$MONTHLY' or 0)
status = 'FAIL' if monthly > 0 else 'PASS'
d['gates']['infracost'] = {'status': status, 'monthlyCostUSD': '$MONTHLY', 'thresholdUSD': 0, 'note': 'baseline is \$0 (local-only infra) — any nonzero monthly cost blocks, per QUESTIONS.pt-BR.md #1'}
d['overall'] = status
print(json.dumps(d, indent=2))
"
