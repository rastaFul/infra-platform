#!/bin/bash
# sonar-scan: Run SonarQube analysis and report results
# Usage: sonar-scan [project-dir] [project-key]
set -euo pipefail

DIR="${1:-.}"
PROJECT_KEY="${2:-$(basename "$(cd "$DIR" && pwd)")}"

cd "$DIR"

# Generate coverage if not present
if [ -f package.json ] && [ ! -f coverage/lcov.info ]; then
  echo "Generating coverage..."
  npx jest --coverage --silent 2>/dev/null || true
fi

# Create sonar-project.properties if missing
if [ ! -f sonar-project.properties ]; then
  cat > sonar-project.properties << EOF
sonar.projectKey=$PROJECT_KEY
sonar.sources=src
sonar.tests=test,tests,__tests__
sonar.javascript.lcov.reportPaths=coverage/lcov.info
sonar.exclusions=node_modules/**,dist/**,coverage/**
EOF
fi

# Run scanner
echo "Running SonarQube analysis for $PROJECT_KEY..."
sonar-scanner -Dsonar.host.url="${SONAR_HOST_URL}" -Dsonar.token="${SONAR_TOKEN:-}" 2>&1

# Wait for analysis
sleep 5

# Get quality gate status
GATE_STATUS=$(curl -s "${SONAR_HOST_URL}/api/qualitygates/project_status?projectKey=${PROJECT_KEY}" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['projectStatus']['status'])" 2>/dev/null || echo "ERROR")

# Get metrics
METRICS=$(curl -s "${SONAR_HOST_URL}/api/measures/component?component=${PROJECT_KEY}&metricKeys=bugs,vulnerabilities,code_smells,coverage,duplicated_lines_density" 2>/dev/null || echo "{}")

echo ""
echo "=== SONAR QUALITY GATE ==="
echo "Status: $GATE_STATUS"
echo ""
echo "=== SONAR METRICS ==="
echo "$METRICS" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    for m in d.get('component',{}).get('measures',[]):
        print(f\"{m['metric']}: {m['value']}\")
except: pass
" 2>/dev/null
echo ""
echo "SONAR_GATE=$GATE_STATUS"
