# Feedback Loop

Autonomous execution cycle with external verification. Allows the agent to work for hours without intervention, with guaranteed quality.

## Cycle

```
STEP → EXECUTE → VERIFY (external tool) →
  ✅ PASS → log result → NEXT STEP
  ❌ FAIL → ANALYZE error → CORRECT → VERIFY again
                              ↓
                    max retries? → ESCALATE to human
```

## Configuration

| Parameter | Infra | Dev |
|-----------|-------|-----|
| maxRetriesPerStep | 3 | 5 |
| maxRetriesGlobal | 10 | 20 |
| verifyTimeout | 120s | 60s |
| pauseOnWarn | true | false |

## Rules

1. **Never skip verification.** Even if the agent "is sure", the external tool validates.
2. **Each retry must be different.** If the same fix failed, try a different approach.
3. **Register every attempt.** Failure reason, attempted fix, result.
4. **Progress saved at every step.** If session drops, resume from last verified step.
5. **Escalation is success, not failure.** Asking human when needed is correct behavior.

## Checkpoints

Every 3 completed steps (or 15 minutes, whichever comes first), save checkpoint in STATE.md.

## Circuit Breaker

| Condition | Action |
|-----------|--------|
| 3 consecutive steps failed | STOP |
| Global retries exceeded spec limit | STOP |
| Total time exceeded spec timeout | STOP |
| Estimated cost exceeded spec limit | STOP |
| More than 50% of steps failed | STOP |

On circuit breaker: save final checkpoint, register reason in audit, generate summary, mark STATE.md as "PAUSED — circuit breaker: [reason]".
