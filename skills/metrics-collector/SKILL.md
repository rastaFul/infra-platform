# Metrics Collector

Collects metrics from each execution to measure agent evolution over time.

## Metrics Collected

| Metric | Type | Description |
|--------|------|-------------|
| duration_seconds | gauge | Total execution time |
| steps_total | counter | Total steps executed |
| steps_passed | counter | Steps that passed first try |
| retries_total | counter | Total retries |
| gates_passed | counter | Gates that passed |
| gates_failed | counter | Gates that failed |
| escalations | counter | Times escalated to human |

## Where to Save

```
.specs/metrics/
├── YYYY-MM-DD-HHMMSS-[task-slug].md   # One entry per execution
└── BENCHMARK.md                         # Accumulated report
```

## Format

```markdown
# Metrics: [task name]
- **Date**: YYYY-MM-DD HH:MM
- **Agent**: harness-infra | harness-dev
- **Task**: [short description]
- **Duration**: Xm Ys
- **Steps**: total=N passed=N retried=N
- **Gates**: passed=N failed=N
- **Escalations**: N
- **Result**: SUCCESS | PARTIAL | FAILED
```

## Rules

1. Collect metrics even on failed executions
2. Never edit previous metrics
3. BENCHMARK.md is recalculated, not manually edited
