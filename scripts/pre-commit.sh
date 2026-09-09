#!/bin/bash
# Local pre-commit gate for infra-platform.
#
# WHY THIS EXISTS: this repo is NOT a JS/TS application (no package.json
# anywhere in the tree) — it's bash scripts (scripts/), real Terraform
# (terraform/), a docker-compose + Grafana/Prometheus/Loki config stack
# (platform/, observability/), and Diátaxis docs (docs/). The JS/TS
# pre-commit template (husky + lint-staged + eslint + tsc + commitlint,
# see skills/code-gates/SKILL.md "husky + lint-staged + commitlint") does
# not apply here — there is nothing in TypeScript/JS to lint. This script
# is the equivalent LOCAL, before-commit gate for this repo's actual
# content types.
#
# WHY A PLAIN GIT HOOK, NOT THE `pre-commit` (Python) FRAMEWORK: this repo
# already has a house style of calling CLI tools directly from small bash
# scripts with `command -v` guards (see skills/*/scripts/run-*.sh) rather
# than adding a new language-specific dependency manager. Introducing the
# `pre-commit` framework would mean a new Python dependency (`pip install
# pre-commit`) and a `.pre-commit-config.yaml` DSL to maintain, for a
# one-shot hook that just shells out to the same tools this script calls
# directly — no net benefit here, and it breaks the "reuse what the repo
# already does" instruction. A native git hook, versioned here (since
# `.git/hooks/` itself is never tracked by git) and installed via a
# one-line wrapper at `.git/hooks/pre-commit`, is the idiomatic minimal
# choice for a polyglot repo with no single package manager.
#
# SCOPE — deliberately narrow and fast (target: a few seconds on a warm
# cache, matching the existing lint-staged.config.cjs comment: "pre-commit
# must not become a multi-minute wait or developers will start using
# --no-verify"):
#   - gitleaks: secret scanning across the STAGED diff only (highest-value
#     check for this repo — it handles .env files, Vault tokens, cloud
#     credentials). Runs over every staged file regardless of extension.
#   - terraform fmt -check + terraform validate: only staged *.tf files,
#     only the real root module(s) they belong to (reuses
#     skills/infra-quality-gates/scripts/find-tf-root.sh — see that
#     script's header for why validating "." or the file's own directory
#     blindly is wrong here).
#   - shellcheck: only staged *.sh files.
#   - YAML/JSON syntax: only staged *.yml/*.yaml/*.json (Grafana
#     dashboards, docker-compose, Prometheus/Loki config, alert rules).
#     Formalizes the ad-hoc `python3 -m json.tool` / `yaml.safe_load`
#     checks already used informally in this project's sessions.
#
# NOT done here (already covered elsewhere, not duplicated):
#   - tflint/kubeconform/pluto (skills/infra-quality-gates) — need
#     provider plugin downloads / are slower, run in CI (gates.yml
#     infra-gates job) and per-task during harness execution, not on
#     every local commit.
#   - conftest/OPA policy gates, tfsec, checkov, trivy config, semgrep,
#     osv-scanner, syft/grype — all already wired into
#     .github/workflows/gates.yml post-push. Duplicating them here would
#     slow down every commit for checks that already gate the PR.
#   - terraform plan/apply — never run against real infra from a commit
#     hook.
#
# A tool missing locally SKIPS that one check (with an install hint) —
# it never silently "passes" and never blocks the whole hook, matching
# every other gate script in this repo (see run-security-gates.sh,
# run-infra-quality.sh: "SKIPPED gates never fail the run; only FAIL
# does").
set -uo pipefail  # NOT -e: run every check and report all failures, don't stop at the first

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT" || exit 1

STAGED="$(git diff --cached --name-only --diff-filter=ACM)"
FAIL=0

pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; FAIL=1; }
skip() { echo "[SKIP] $1 -- $2"; }

echo "=== pre-commit gate (infra-platform) ==="

if [ -z "$STAGED" ]; then
  echo "(no staged files — nothing to check)"
  exit 0
fi

# ---- 1. gitleaks: secret scanning across the staged diff ----
if command -v gitleaks >/dev/null 2>&1; then
  GITLEAKS_OUT="$(mktemp)"
  if gitleaks protect --staged --redact -v >"$GITLEAKS_OUT" 2>&1; then
    pass "gitleaks (no secrets in staged changes)"
  else
    fail "gitleaks (possible secret in staged changes)"
    sed 's/^/  /' "$GITLEAKS_OUT"
  fi
  rm -f "$GITLEAKS_OUT"
else
  skip "gitleaks" "not installed -- see skills/security-gates/SKILL.md, or: https://github.com/gitleaks/gitleaks/releases (pin the same version as .harness-sandbox/docker/Dockerfile.sandbox)"
fi

# ---- 2. terraform fmt -check + validate — only staged *.tf files ----
TF_STAGED="$(echo "$STAGED" | grep -E '\.tf$' || true)"
if [ -n "$TF_STAGED" ]; then
  if command -v terraform >/dev/null 2>&1; then
    FMT_BAD=""
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      terraform fmt -check -diff "$f" >/tmp/tffmt-precommit.out 2>&1 || FMT_BAD="$FMT_BAD $f"
    done <<<"$TF_STAGED"
    if [ -z "$FMT_BAD" ]; then
      pass "terraform fmt -check ($(echo "$TF_STAGED" | wc -l | tr -d ' ') file(s))"
    else
      fail "terraform fmt -check --$FMT_BAD not formatted (run: terraform fmt <file>)"
    fi

    # Validate every real root module that has a staged .tf file under it
    # (a staged change to a reusable module under terraform/modules/ still
    # needs the consuming root re-validated, so this validates ALL
    # discovered roots whenever any .tf file is staged, not just a
    # path-prefix match against the staged file itself).
    ROOTS="$(bash skills/infra-quality-gates/scripts/find-tf-root.sh . 2>/dev/null || true)"
    if [ -n "$ROOTS" ]; then
      while IFS= read -r r; do
        [ -z "$r" ] && continue
        if (cd "$r" && terraform init -backend=false -input=false >/tmp/tfinit-precommit.out 2>&1 && terraform validate >/tmp/tfvalidate-precommit.out 2>&1); then
          pass "terraform validate ($r)"
        else
          fail "terraform validate ($r)"
          tail -20 /tmp/tfvalidate-precommit.out 2>/dev/null | sed 's/^/  /'
        fi
      done <<<"$ROOTS"
    fi
  else
    skip "terraform fmt/validate" "terraform not installed -- https://developer.hashicorp.com/terraform/install"
  fi
fi

# ---- 3. shellcheck — only staged *.sh files ----
SH_STAGED="$(echo "$STAGED" | grep -E '\.sh$' || true)"
if [ -n "$SH_STAGED" ]; then
  if command -v shellcheck >/dev/null 2>&1; then
    SH_BAD=0
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      SC_OUT="$(mktemp)"
      if ! shellcheck "$f" >"$SC_OUT" 2>&1; then
        SH_BAD=$((SH_BAD + 1))
        fail "shellcheck: $f"
        sed 's/^/  /' "$SC_OUT"
      fi
      rm -f "$SC_OUT"
    done <<<"$SH_STAGED"
    [ "$SH_BAD" -eq 0 ] && pass "shellcheck ($(echo "$SH_STAGED" | wc -l | tr -d ' ') file(s))"
  else
    skip "shellcheck" "not installed -- https://github.com/koalaman/shellcheck/releases or 'apt install shellcheck'"
  fi
fi

# ---- 4. YAML / JSON syntax — Grafana dashboards, compose files, alert rules ----
YAML_STAGED="$(echo "$STAGED" | grep -E '\.(yml|yaml)$' || true)"
if [ -n "$YAML_STAGED" ]; then
  YAML_BAD=0
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    YERR="$(mktemp)"
    if ! python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$f" 2>"$YERR"; then
      YAML_BAD=$((YAML_BAD + 1))
      fail "yaml syntax: $f"
      sed 's/^/  /' "$YERR"
    fi
    rm -f "$YERR"
  done <<<"$YAML_STAGED"
  [ "$YAML_BAD" -eq 0 ] && pass "yaml syntax ($(echo "$YAML_STAGED" | wc -l | tr -d ' ') file(s))"
fi

JSON_STAGED="$(echo "$STAGED" | grep -E '\.json$' || true)"
if [ -n "$JSON_STAGED" ]; then
  JSON_BAD=0
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    JERR="$(mktemp)"
    if ! python3 -m json.tool "$f" >/dev/null 2>"$JERR"; then
      JSON_BAD=$((JSON_BAD + 1))
      fail "json syntax: $f"
      sed 's/^/  /' "$JERR"
    fi
    rm -f "$JERR"
  done <<<"$JSON_STAGED"
  [ "$JSON_BAD" -eq 0 ] && pass "json syntax ($(echo "$JSON_STAGED" | wc -l | tr -d ' ') file(s))"
fi

echo "=========================="
if [ "$FAIL" -eq 1 ]; then
  echo "pre-commit gate: FAIL -- commit blocked. Fix the issues above."
  echo "(bypass only in a genuine emergency: git commit --no-verify -- not recommended, see CLAUDE.md 'External Verification' principle)"
  exit 1
fi
echo "pre-commit gate: PASS"
exit 0
