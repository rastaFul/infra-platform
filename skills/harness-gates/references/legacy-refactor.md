# Legacy & Partial Refactor — Progressive Gates

## The Problem

Legacy code won't pass standard gates. If you require 100% compliance, nothing gets done. But if you disable gates, you lose protection.

## Solution: Progressive Gates

In legacy projects, gates operate at two levels:

### Level 1: Baseline (what already exists)
- Capture current state BEFORE any change
- Run gates and register result as baseline
- This baseline does NOT need to pass — it's the starting point

### Level 2: Delta (what you changed)
- Gates evaluate ONLY new/modified code
- Rule: **don't make it worse**. The delta cannot introduce new problems.
- Rule: **improve where you touch**. If you modify a file, apply standards to that file.

## Flow

```
1. BASELINE  → run gates on current state → save result
2. IMPLEMENT → make the change
3. DELTA     → run gates again → compare with baseline
4. EVALUATE  → did delta introduce new problems?
   ✅ Didn't worsen (or improved) → PASS
   ❌ Worsened → FAIL — fix before proceeding
```

## Strangler Fig Pattern

For gradual migrations:

```
Legacy code (works, don't touch)
       ↓ calls
Adapter/Facade (new, with standards)
       ↓ calls
New code (Clean Architecture, TS, tests)
```

New code follows all gates. Legacy stays untouched. The adapter is the bridge.
