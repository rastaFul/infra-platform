# Session Memory — Napkin

> Tactical knowledge layer per repository. Complements STATE.md and DECISIONS.md.

## File

`.claude/napkin.md` — one file per repository, scoped to this project.

## Session Start Protocol

**Every session**: read `.claude/napkin.md` alongside STATE.md and DECISIONS.md.
Apply context from napkin BEFORE creating any spec or starting any task.

## Write Protocol

Write to napkin.md immediately when:
- User corrects agent behavior (any correction)
- An approach fails and agent switches strategy
- Unexpected environment behavior discovered
- A pattern works well and is worth repeating

## Boundaries

| What happened | Where it goes |
|---------------|--------------|
| User corrects agent behavior | napkin.md |
| Approach failed → alternative worked | napkin.md |
| Architecture / design decision | DECISIONS.md |
| Task status / progress | STATE.md |
| Global user preference | CLAUDE.md (user global) |

## Entry Format

```
- [YYYY-MM-DD] [component/context] → [problem] → [what works]
```

## Maintenance

- Consolidate every 10 entries: remove outdated, merge similar
- Max ~100 entries before major consolidation
- Commit or gitignore: user decides (team visibility vs personal)

## What Napkin Is NOT

- Not a gate — never blocks execution
- Not a spec — never defines requirements
- Not a decision log — tactical corrections only, not architecture
