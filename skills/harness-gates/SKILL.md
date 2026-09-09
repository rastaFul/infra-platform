# Harness Gates

Mandatory checkpoints that protect against unintended consequences. Every action that modifies state MUST pass through gates.

## Core Principle

**The agent does NOT validate itself.** External, deterministic tools validate. The agent orchestrates the validation flow.

## Gate Flow

```
REQUEST → PRE-GATES → DRY-RUN → APPROVAL → EXECUTE → POST-GATES → REGISTER
```

## Pre-Gates (BEFORE execution)

1. **Spec Validation** — Action has a spec? Within scope? If no spec → BLOCK.
2. **Policy Check** — Violates hard policy? If yes → BLOCK.
3. **Dry-Run** — Execute preview (terraform plan, kubectl diff, helm template). If fails → BLOCK.
4. **Blast Radius** — How many resources? Reversible? LOW (≤3, reversible), MEDIUM (4-10), HIGH (>10 or irreversible). If HIGH → require human approval.
5. **Cost Estimation** — If cost increase > threshold → flag for review.
6. **Rollback Plan** — Document how to revert BEFORE executing.

## Post-Gates (AFTER execution)

7. **Verification** — Run verification criteria from spec using external tools.
8. **Registration** — Log to audit trail, update STATE.md, record metrics.

## Escalation Rules

Stop and ask human when:
- Blast radius is HIGH
- Any gate fails 3 times consecutively
- Action is irreversible and no rollback plan exists
- Cost estimate exceeds threshold
- Uncertainty about business rule
- Action targets production environment

## References

- [policies.md](references/policies.md) — Hard policies
- [escalation.md](references/escalation.md) — Escalation rules
- [autonomous-spec-template.md](references/autonomous-spec-template.md) — Template for autonomous execution
- [legacy-refactor.md](references/legacy-refactor.md) — Progressive gates for legacy code
- [drift-detection.md](references/drift-detection.md) — Drift detection procedures
