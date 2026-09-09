# Spec Manager

Scripts to create and manage the `.specs/` project structure.

## Scripts

### Initialize project
```bash
bash skills/spec-manager/scripts/init-project.sh <project-dir> <project-name> <description>
```

### Create feature spec
```bash
bash skills/spec-manager/scripts/create-spec.sh <project-dir> <feature-name> <description>
```

### Update state
```bash
bash skills/spec-manager/scripts/update-state.sh <project-dir> <status> [task-name] [task-status]
```

### Create retrospec (quick mode)
```bash
bash skills/spec-manager/scripts/create-retrospec.sh <project-dir> <feature-name> <description> <files-changed> <decisions>
```

### Create UX journey (SIGNIFICANT UI changes — see `skills/ux-journey/SKILL.md`)
```bash
bash skills/spec-manager/scripts/create-journey.sh <project-dir> <feature-name> <goal>
```

### Extract evaluator-safe journey brief (strips Happy Path)
```bash
bash skills/spec-manager/scripts/extract-journey-brief.sh <project-dir> <feature-name>
```
