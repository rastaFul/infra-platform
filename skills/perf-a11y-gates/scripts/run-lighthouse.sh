#!/bin/bash
# Runs Lighthouse CI against a running local URL. THRESHOLD DECIDED
# (QUESTIONS.pt-BR.md #2, 2026-09): minimum 90/100 on all 4 categories
# (performance, accessibility, best-practices, SEO) — Google's own
# documented "green" band for Lighthouse scoring (0-49 red, 50-89 orange,
# 90-100 green: https://developer.chrome.com/docs/lighthouse/performance/performance-scoring),
# the de-facto market bar for "good" used across CI Lighthouse gates. User
# explicitly asked for all categories to block, not just performance.
set -euo pipefail

LH_MIN_PERFORMANCE="${LH_MIN_PERFORMANCE:-90}"
LH_MIN_ACCESSIBILITY="${LH_MIN_ACCESSIBILITY:-90}"
LH_MIN_BEST_PRACTICES="${LH_MIN_BEST_PRACTICES:-90}"
LH_MIN_SEO="${LH_MIN_SEO:-90}"

URL="${1:?Usage: run-lighthouse.sh <url>}"
RESULT='{"timestamp":"'"$(date -Iseconds)"'","gates":{},"overall":"PASS"}'

if ! command -v lhci &>/dev/null; then
  echo '{"timestamp":"'"$(date -Iseconds)"'","gates":{"lighthouse":{"status":"SKIPPED","reason":"@lhci/cli not installed"}},"overall":"SKIPPED"}'
  exit 0
fi

if ! curl -sf --max-time 5 "$URL" >/dev/null 2>&1; then
  echo '{"timestamp":"'"$(date -Iseconds)"'","gates":{"lighthouse":{"status":"SKIPPED","reason":"target URL not reachable: '"$URL"'"}},"overall":"SKIPPED"}'
  exit 0
fi

OUT_DIR=$(mktemp -d)
lhci collect --url="$URL" --numberOfRuns=1 --outputDir="$OUT_DIR" >/dev/null 2>&1 || true
REPORT=$(find "$OUT_DIR" -name "*.report.json" | head -1)

if [ -z "$REPORT" ]; then
  echo '{"timestamp":"'"$(date -Iseconds)"'","gates":{"lighthouse":{"status":"FAIL","reason":"lhci produced no report"}},"overall":"FAIL"}'
  exit 0
fi

python3 -c "
import json
d = json.loads('$RESULT')
r = json.load(open('$REPORT'))
cats = r.get('categories', {})
perf = round(cats.get('performance', {}).get('score', 0) * 100)
a11y = round(cats.get('accessibility', {}).get('score', 0) * 100)
bp = round(cats.get('best-practices', {}).get('score', 0) * 100)
seo = round(cats.get('seo', {}).get('score', 0) * 100)
mins = {'performance': $LH_MIN_PERFORMANCE, 'accessibility': $LH_MIN_ACCESSIBILITY, 'best-practices': $LH_MIN_BEST_PRACTICES, 'seo': $LH_MIN_SEO}
scores = {'performance': perf, 'accessibility': a11y, 'best-practices': bp, 'seo': seo}
status = 'PASS' if all(scores[k] >= mins[k] for k in mins) else 'FAIL'
d['gates']['lighthouse'] = {
    'status': status,
    'performance': perf,
    'accessibility': a11y,
    'best-practices': bp,
    'seo': seo,
    'thresholds': mins,
    'note': 'threshold: 90/100 all categories (Google Lighthouse green band) — QUESTIONS.pt-BR.md #2'
}
d['overall'] = status
print(json.dumps(d, indent=2))
"
