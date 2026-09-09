# Audit Trail

Complete logging of everything the agent does. Not optional.

## What to Register

Every action that modifies state (file, cloud resource, deploy, config):

```markdown
## [YYYY-MM-DD HH:MM] ACTION_TYPE

- **Spec**: [which spec authorized — link or "ad-hoc"]
- **Action**: [what was done]
- **Target**: [file, resource, service affected]
- **Gates**: [which gates passed — list]
- **Result**: SUCCESS | FAILURE | PARTIAL | ESCALATED
- **Rollback**: [how to revert, if applicable]
```

## Where to Save

```
.specs/audit/
├── YYYY-MM-DD.md    # One file per day
└── summary.md       # Accumulated summary
```

## Rules

1. Never omit an action from the audit trail
2. Read-only actions don't need full registration
3. Audit trail is append-only — never edit previous entries
4. If the agent cannot register (write error), STOP and escalate
