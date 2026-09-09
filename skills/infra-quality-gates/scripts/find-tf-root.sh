#!/bin/bash
# Detects Terraform ROOT module directories in a repo — as opposed to
# reusable modules referenced via `module` blocks from elsewhere.
#
# BUG FOUND AND FIXED via a real product-repo rollout (infra-platform,
# 2026-09-09): gates.yml's infra-gates job used to run `terraform
# validate`/`terraform plan` directly against the repo root ("."). That
# works only when .tf files live at the repo root. Real repos commonly
# nest them (this exact repo: terraform/environments/oci-free/ as the
# root module, terraform/modules/oci-compute/ as a reusable module it
# calls) — `terraform validate` against an empty root directory silently
# "passes" (an empty configuration is trivially valid — a false positive,
# it validates NOTHING), and `terraform plan` hard-fails with "No
# configuration files". tfsec/checkov didn't have this problem because
# they scan recursively by design; `terraform validate`/`plan` don't.
#
# Heuristic: any directory containing .tf files that is NOT referenced as
# a local module source (`source = "../..."` or "./...") by any other .tf
# file in the repo is a root module candidate. Prints one directory per
# line (a repo can have more than one environment/root) — prints nothing
# if no .tf files exist at all (caller should treat that as SKIPPED, not
# an error).
set -euo pipefail
DIR="${1:-.}"
cd "$DIR"

ALL_TF_DIRS=$(find . -maxdepth 8 -name "*.tf" -not -path "*/.terraform/*" 2>/dev/null | xargs -r -n1 dirname | sort -u)
[ -z "$ALL_TF_DIRS" ] && exit 0

REFERENCED=$(mktemp)
# NOTE: the inner `grep ... | sed ... | while read` pipeline must end in
# `|| true` — same unprotected-grep bug class found (and fixed) 4 times
# already this session elsewhere: grep legitimately exits 1 when a .tf
# file has no module `source =` line at all (the common case for a leaf
# module or a root with no children), which under set -e/pipefail would
# otherwise crash this whole script.
while IFS= read -r tf_dir; do
  [ -z "$tf_dir" ] && continue
  while IFS= read -r tf_file; do
    [ -z "$tf_file" ] && continue
    # BUG caught before wiring this into gates.yml (own fixture test):
    # resolving with --relative-to=. from *inside* $tf_dir produced a path
    # relative to $tf_dir ("../../modules/oci-compute"), but the second
    # loop below resolves candidates relative to the repo root
    # ("terraform/modules/oci-compute") — never matched, every module got
    # wrongly reported as a root too. Resolve to an ABSOLUTE path here
    # instead so both sides compare the same way.
    grep -hoE 'source[[:space:]]*=[[:space:]]*"\.\.?/[^"]+"' "$tf_file" 2>/dev/null \
      | sed -E 's/.*"(.*)"/\1/' \
      | while IFS= read -r rel; do
          (cd "$tf_dir" && realpath -m "$rel" 2>/dev/null) >>"$REFERENCED" || true
        done || true
  done < <(find "$tf_dir" -maxdepth 1 -name "*.tf" 2>/dev/null)
done <<<"$ALL_TF_DIRS"

FOUND_ROOT=0
while IFS= read -r d; do
  [ -z "$d" ] && continue
  norm=$(realpath -m "$d")
  if ! grep -qxF "$norm" "$REFERENCED" 2>/dev/null; then
    echo "$d"
    FOUND_ROOT=1
  fi
done <<<"$ALL_TF_DIRS"
rm -f "$REFERENCED"

# Fallback: every directory got referenced as someone's module (unusual,
# e.g. a repo that's ALL reusable modules with no root) — rather than
# print nothing (which the caller would treat as "no terraform"), fall
# back to the shallowest directory so validate/tfsec/checkov still run
# against *something* real instead of silently skipping real .tf files.
if [ "$FOUND_ROOT" -eq 0 ]; then
  echo "$ALL_TF_DIRS" | awk '{print length, $0}' | sort -n | head -1 | cut -d' ' -f2-
fi
