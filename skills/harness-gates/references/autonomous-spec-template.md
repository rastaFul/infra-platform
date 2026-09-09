# Autonomous Execution Spec Template

Use this template when you want the agent to run autonomously. All fields are mandatory.

```markdown
# Spec: [task name]

## Intent
[What must be done — clear and measurable objective]

## Scope

### In scope
- [file/resource/service that can be modified]

### Out of scope (DO NOT touch)
- [file/resource/service that CANNOT be modified]

## Constraints
- [rule 1 — e.g., "do not alter public APIs"]
- [rule 2 — e.g., "maintain backward compatibility"]

## Tasks (in order)
1. [task 1] → verify with: [tool]
2. [task 2] → verify with: [tool]
3. [task N] → verify with: [tool]

## Done When
- [ ] [verifiable criterion 1 — e.g., "npm test passes with 0 failures"]
- [ ] [verifiable criterion 2 — e.g., "tfsec returns 0 critical"]

## Execution Limits
- **Global timeout**: [e.g., 2h]
- **Max retries per step**: [e.g., 3]
- **Max retries global**: [e.g., 15]
- **Max estimated cost**: [e.g., $5 in tokens]
- **Circuit breaker**: stop if [e.g., "3 consecutive steps fail"]

## When in doubt
- [default decision 1 — e.g., "if ambiguous, choose the most conservative option"]
- [default decision 2 — e.g., "if missing business rule, skip and register in DECISIONS.md"]

## Notification
- On completion: [e.g., "save summary in .specs/audit/"]
- On escalation stop: [e.g., "save state and list pending items"]
```
