# Audit Writer

Scripts to register audit trail entries, metrics, and execution summaries.

## Scripts

### Log task result
```bash
bash skills/audit-writer/scripts/log-task.sh <project-dir> <task-number> <task-name> <gates-json>
```

### Log execution summary
```bash
bash skills/audit-writer/scripts/log-summary.sh <project-dir> <total> <done> <failed> <gates-json> <files-changed>
```

### Create metrics file
```bash
bash skills/audit-writer/scripts/log-metrics.sh <project-dir> <task-name> <duration> <gates-json> <result>
```

### Log ux-journey-judge result (execution.md + `.ux.md` metrics file)
```bash
bash skills/audit-writer/scripts/log-ux-result.sh <project-dir> <feature-name> <result-json>
```
