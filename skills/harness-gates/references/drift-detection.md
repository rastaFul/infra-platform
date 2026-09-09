# Drift Detection

## What It Is

Drift = real state diverged from expected state. Someone made a manual change, a deploy partially failed, or a resource was modified outside Terraform/Helm.

## When to Run

1. **Start of every execution** — before any change, check drift
2. **Post-deploy** — confirm real state matches expected
3. **On demand** — when user asks "check drift"

## How to Detect

| Context | Command | What it compares |
|---------|---------|-----------------|
| Terraform | `terraform plan` | State file vs real cloud resources |
| Kubernetes | `kubectl diff -f manifest.yaml` | Local manifest vs cluster |
| Helm | `helm get values release -n ns` vs local values | Applied vs expected values |

## Flow

```
1. DETECT  → run drift commands
2. ANALYZE → is there drift?
   ✅ No drift → proceed normally
   ⚠️ Drift detected → classify
3. CLASSIFY
   - SAFE: cosmetic drift (labels, annotations) → register and proceed
   - WARN: functional drift (replicas, env vars) → inform user, request decision
   - CRITICAL: structural drift (missing resources, wrong config) → BLOCK, escalate
4. DECIDE
   - Fix drift before proceeding?
   - Incorporate drift as new baseline?
   - Register in DECISIONS.md
```
