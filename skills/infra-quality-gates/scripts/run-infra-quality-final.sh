#!/bin/bash
# Final infra QUALITY gates (run WHEN FINISHING all tasks): terraform-docs
# (check mode), Polaris, kube-linter. Returns JSON.
#
# Cadence: harness-infra.md rule 2, "WHEN FINISHING all tasks" — same point
# where all security gates (terraform validate/tfsec/checkov/kube-score) are
# re-run for final validation. These three are slower / more holistic than
# the per-task gates in run-infra-quality.sh (tflint, kubeconform, pluto) so
# they don't run after every single task.
#
# kube-linter here closes a documented gap: claude/.claude/agents/harness-infra.md
# cited kube-linter as a verification tool (rule 3) but it was never added to
# Dockerfile.sandbox. This script assumes that gap has been closed in the
# image; if kube-linter is still missing, this gate reports SKIPPED rather
# than silently passing.
#
# Same limitation as run-infra-quality.sh: Polaris and kube-linter need real
# K8s manifests, not raw Helm chart templates (Go template syntax). Render
# charts first (`helm template`) before pointing these at Helm chart source.
set -euo pipefail
DIR="${1:-.}"
cd "$DIR"

RESULT='{"timestamp":"'$(date -Iseconds)'","gates":{},"overall":"PASS"}'

# --- terraform-docs: module documentation is current (check mode, no silent regeneration) ---
if ! command -v terraform-docs &>/dev/null; then
  TFDOCS_STATUS="SKIPPED"; TFDOCS_CHECKED=0; TFDOCS_STALE=0; TFDOCS_NOTE="terraform-docs not installed"
else
  # BUG FOUND AND FIXED via real execution (QUESTIONS.pt-BR.md #15/#16
  # verification pass, 2026-09): without `-r`, both BusyBox's and GNU's
  # xargs run the given command ONCE EVEN WITH EMPTY STDIN (calling
  # `dirname` with zero args), which errors and makes xargs exit 123 — with
  # `set -euo pipefail` above, that crashed this ENTIRE final gate script
  # (not just this one gate) on any repo with zero .tf files, a completely
  # ordinary case (e.g. a pure-app or k8s-only repo). Reproduced against a
  # real k8s-only fixture, fixed with `-r` (BusyBox: "don't run command if
  # input is empty"; GNU: `--no-run-if-empty`, same short flag), and
  # re-verified the fix directly against the same fixture before writing
  # this comment.
  MODULE_DIRS=$(find . -maxdepth 8 -name "*.tf" -not -path "*/.terraform/*" 2>/dev/null | xargs -r -n1 dirname 2>/dev/null | sort -u)
  if [ -z "$MODULE_DIRS" ]; then
    TFDOCS_STATUS="SKIPPED"; TFDOCS_CHECKED=0; TFDOCS_STALE=0; TFDOCS_NOTE="no .tf modules found"
  else
    TFDOCS_CHECKED=0
    TFDOCS_STALE=0
    for d in $MODULE_DIRS; do
      if [ -f "$d/README.md" ]; then
        TFDOCS_CHECKED=$((TFDOCS_CHECKED + 1))
        terraform-docs markdown table --output-file README.md --output-check "$d" >/dev/null 2>&1 || TFDOCS_STALE=$((TFDOCS_STALE + 1))
      fi
    done
    if [ "$TFDOCS_CHECKED" -eq 0 ]; then
      TFDOCS_STATUS="SKIPPED"; TFDOCS_NOTE="no module has a README.md yet to check currency against (run terraform-docs once to generate a baseline first)"
    elif [ "$TFDOCS_STALE" -gt 0 ]; then
      TFDOCS_STATUS="FAIL"; TFDOCS_NOTE="$TFDOCS_STALE of $TFDOCS_CHECKED module README(s) out of date"
    else
      TFDOCS_STATUS="PASS"; TFDOCS_NOTE=""
    fi
  fi
fi
RESULT=$(echo "$RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);d['gates']['terraform_docs']={'status':'$TFDOCS_STATUS','checked':$TFDOCS_CHECKED,'stale':$TFDOCS_STALE,'note':'$TFDOCS_NOTE'};print(json.dumps(d))")

# --- Polaris: Kubernetes best-practice scoring (complements kube-score) ---
if ! command -v polaris &>/dev/null; then
  POLARIS_STATUS="SKIPPED"; POLARIS_DANGER=0; POLARIS_WARNING=0; POLARIS_NOTE="polaris not installed"
else
  K8S_FILES=$(find . -maxdepth 6 \( -name "*.yaml" -o -name "*.yml" \) -not -path "*/.terraform/*" -not -path "*/node_modules/*" -not -path "*/templates/*" 2>/dev/null | head -1)
  if [ -z "$K8S_FILES" ]; then
    POLARIS_STATUS="SKIPPED"; POLARIS_DANGER=0; POLARIS_WARNING=0; POLARIS_NOTE="no plain k8s manifest yaml/yml found (raw Helm templates excluded, see script header)"
  else
    # --set-exit-code-on-danger is Polaris's own default-severity flag (danger
    # is Polaris's built-in top severity), not a threshold invented here.
    # BUG FOUND AND FIXED via real execution (QUESTIONS.pt-BR.md #15/#16
    # verification pass, 2026-09): this used to merge stderr into the
    # captured output (`2>&1`). Polaris logs a line to STDERR even in
    # --format json mode (confirmed live:
    # `time="..." level=info msg="3 danger items found in audit"`), which
    # corrupted the JSON stream fed to the python parser below — json.load
    # silently threw, the except block returned 0, so danger/warning were
    # ALWAYS reported as 0 regardless of real findings (PASS/FAIL itself
    # stayed correct since that's driven by the exit code, not this parse
    # — but the informational counts were always wrong). Fixed by keeping
    # stdout and stderr separate (`2>/dev/null` instead of `2>&1`) — stderr
    # isn't needed here at all.
    POLARIS_OUT=$(polaris audit --audit-path . --format json --set-exit-code-on-danger 2>/dev/null) && POLARIS_STATUS="PASS" || POLARIS_STATUS="FAIL"
    # Informational counts. VERIFIED 2026-09 against a real Polaris v10.2.2
    # run (QUESTIONS.pt-BR.md #16) — there is NO top-level
    # DangerResultCount/WarningResultCount field at all (confirmed real top
    # keys: AuditTime, ClusterInfo, DisplayName, PolarisOutputVersion,
    # Results, Score, SourceName, SourceType). Real counts require walking
    # Results[].PodResult.Results{} and
    # Results[].PodResult.ContainerResults[].Results{}, each a dict of
    # check-id -> {Success, Severity: "danger"|"warning", ...}, counting
    # entries where Success is false. PASS/FAIL above remains authoritative
    # (Polaris's own exit code) regardless of this parse — these are
    # informational counts only.
    POLARIS_DANGER=$(echo "$POLARIS_OUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print(0); sys.exit()
danger = 0
def count(results):
    global danger
    for r in (results or {}).values():
        if not r.get('Success', True) and r.get('Severity') == 'danger':
            danger += 1
for item in (d.get('Results') or []):
    pod = item.get('PodResult') or {}
    count(pod.get('Results'))
    for cr in (pod.get('ContainerResults') or []):
        count(cr.get('Results'))
print(danger)
" 2>/dev/null || echo 0)
    POLARIS_WARNING=$(echo "$POLARIS_OUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print(0); sys.exit()
warning = 0
def count(results):
    global warning
    for r in (results or {}).values():
        if not r.get('Success', True) and r.get('Severity') == 'warning':
            warning += 1
for item in (d.get('Results') or []):
    pod = item.get('PodResult') or {}
    count(pod.get('Results'))
    for cr in (pod.get('ContainerResults') or []):
        count(cr.get('Results'))
print(warning)
" 2>/dev/null || echo 0)
    [ -z "$POLARIS_DANGER" ] && POLARIS_DANGER=0
    [ -z "$POLARIS_WARNING" ] && POLARIS_WARNING=0
    POLARIS_NOTE=""
  fi
fi
RESULT=$(echo "$RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);d['gates']['polaris']={'status':'$POLARIS_STATUS','danger':$POLARIS_DANGER,'warning':$POLARIS_WARNING,'note':'$POLARIS_NOTE'};print(json.dumps(d))")

# --- kube-linter: K8s manifest best-practice lint (fixes documented install gap) ---
if ! command -v kube-linter &>/dev/null; then
  KL_STATUS="SKIPPED"; KL_REPORTS=0; KL_NOTE="kube-linter not installed (documented gap: cited in harness-infra.md but missing from Dockerfile.sandbox — see infra-quality-gates SKILL.md)"
else
  K8S_FILES=$(find . -maxdepth 6 \( -name "*.yaml" -o -name "*.yml" \) -not -path "*/.terraform/*" -not -path "*/node_modules/*" -not -path "*/templates/*" 2>/dev/null | head -1)
  if [ -z "$K8S_FILES" ]; then
    KL_STATUS="SKIPPED"; KL_REPORTS=0; KL_NOTE="no plain k8s manifest yaml/yml found (raw Helm templates excluded, see script header)"
  else
    # BUG FOUND AND FIXED via real execution (same pass as the Polaris fix
    # above): kube-linter also writes to STDERR even in --format json mode
    # (confirmed live: "Error: found 5 lint errors"), which corrupted the
    # JSON when merged via 2>&1 — KL_REPORTS was always 0 regardless of
    # real findings. Fixed the same way: keep stdout/stderr separate.
    KL_OUT=$(kube-linter lint . --format json 2>/dev/null) && KL_STATUS="PASS" || KL_STATUS="FAIL"
    KL_REPORTS=$(echo "$KL_OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d.get('Reports') or []))" 2>/dev/null || echo 0)
    [ -z "$KL_REPORTS" ] && KL_REPORTS=0
    KL_NOTE=""
  fi
fi
RESULT=$(echo "$RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);d['gates']['kube_linter']={'status':'$KL_STATUS','reports':$KL_REPORTS,'note':'$KL_NOTE'};print(json.dumps(d))")

# Overall (SKIPPED gates never fail the run; only FAIL does)
echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d['gates'].values():
    if g['status']=='FAIL': d['overall']='FAIL'; break
print(json.dumps(d,indent=2))
"
