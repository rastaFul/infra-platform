#!/bin/bash
# Activates the local pre-commit gate (husky + lint-staged + commitlint) in a
# target TypeScript/Node.js project, and places the other dev-quality config
# templates (dependency-cruiser, jscpd, Stryker) at the project root.
#
# Run from the TARGET project root, after:
#   1. install.sh has copied templates/dev-quality/ into the target project
#   2. `npm install -D` has been run with the devDependencies listed in
#      claude/skills/code-gates/SKILL.md ("Dev quality gates" section)
#
# Usage (from target project root):
#   bash templates/dev-quality/husky/setup-husky.sh
set -euo pipefail

if [ ! -d .git ]; then
  echo "Not a git repo root (no .git/) — run from the target project root." >&2
  exit 1
fi

TEMPLATE_DIR="$(cd "$(dirname "$0")" && pwd)"
DEV_QUALITY_DIR="$(cd "$TEMPLATE_DIR/.." && pwd)"

# husky v9: creates .husky/ and wires core.hooksPath + package.json "prepare"
npx --yes husky init

# Overwrite the default hooks husky init generates with our templates
cp "$TEMPLATE_DIR/pre-commit" .husky/pre-commit
cp "$TEMPLATE_DIR/commit-msg" .husky/commit-msg
chmod +x .husky/pre-commit .husky/commit-msg

# Place the other dev-quality configs at the project root (where each gate
# script and its underlying tool expects to find them by default filename)
cp "$DEV_QUALITY_DIR/lint-staged.config.cjs" ./lint-staged.config.cjs
cp "$DEV_QUALITY_DIR/commitlint.config.cjs" ./commitlint.config.cjs
cp "$DEV_QUALITY_DIR/.dependency-cruiser.cjs" ./.dependency-cruiser.cjs
cp "$DEV_QUALITY_DIR/.jscpd.json" ./.jscpd.json
cp "$DEV_QUALITY_DIR/stryker.conf.json" ./stryker.conf.json

echo "husky pre-commit + commit-msg hooks installed."
echo "Config files copied to project root: lint-staged.config.cjs, commitlint.config.cjs, .dependency-cruiser.cjs, .jscpd.json, stryker.conf.json"
echo ""
echo "If you have not installed devDependencies yet, run:"
echo "  npm install -D husky lint-staged @commitlint/cli @commitlint/config-conventional dependency-cruiser eslint-plugin-sonarjs jscpd @stryker-mutator/core @stryker-mutator/jest-runner"
