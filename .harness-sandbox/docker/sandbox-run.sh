#!/bin/bash
# Launch the harness sandbox environment
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="${1:-$(pwd)}"

echo "🚀 Starting Harness Sandbox..."
echo "   Workspace: $WORKSPACE"
echo "   SonarQube: http://localhost:9000 (admin/admin on first run)"

export WORKSPACE
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d sonarqube
docker compose -f "$SCRIPT_DIR/docker-compose.yml" run --rm \
  -v "$WORKSPACE:/workspace" \
  sandbox
