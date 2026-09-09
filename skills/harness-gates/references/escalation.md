# Escalation Rules

## When to escalate to human

| Condition | Action |
|-----------|--------|
| Blast radius HIGH (>10 resources or irreversible) | Stop, show impact, request approval |
| Gate failed 3x consecutively | Stop, show failure history, request input |
| Irreversible action without rollback plan | Stop, explain risk, request approval |
| Estimated cost > significant increase | Stop, show estimate, request approval |
| Uncertainty about business rule | Stop, ask before assuming |
| Target = production | Always request explicit approval |
| Conflict between policies | Stop, show conflict, request decision |
| Verification tool unavailable | Stop, do not proceed without verification |

## Escalation format

```markdown
## ⚠️ Escalation Required

**Reason**: [which condition triggered]
**Context**: [what was being done]
**Impact**: [blast radius, cost, reversibility]
**Options**:
1. [option A]
2. [option B]
3. Cancel

**Awaiting human decision.**
```

## After human decision

- Register decision in DECISIONS.md
- Proceed or cancel as instructed
- Never repeat the same escalation in the same session if already decided
