# Napkin

Session memory layer for tactical knowledge per repository. Records mistakes, corrections, and successful patterns so they're not repeated. Source: https://github.com/blader/napkin

## Protocol

**READ**: At every session start, read `.claude/napkin.md` alongside STATE.md and DECISIONS.md.

**WRITE immediately** when:
- User corrects agent behavior (any correction, no matter how small)
- An approach fails and agent switches to alternative strategy
- Unexpected environment behavior is discovered (lib version, bundler quirk, framework behavior)
- A pattern works well and is worth repeating in this project

## File

`.claude/napkin.md` — one file per repository

## Entry Format

```
- [YYYY-MM-DD] [component/context] → [problem] → [what works]
```

Examples:
```
- [2026-05-08] UserCard → useEffect caused infinite re-render on state derivation → use useMemo
- [2026-05-08] Playwright gate → fails if dev server not on :3000 → curl check before invoking
- [2026-05-08] TokenInput → breaks with children as array → always wrap in Fragment
```

## Boundaries

| Event | Destination |
|-------|------------|
| User corrects agent | napkin.md |
| Approach failed → alternative worked | napkin.md |
| Architecture decision | DECISIONS.md |
| Task progress / status | STATE.md |
| Global user preference | CLAUDE.md (global) |

## Rules

1. 3 lines max per entry: context → problem → solution
2. No duplication — check STATE.md and DECISIONS.md first
3. No sensitive data — no tokens, passwords, absolute machine paths
4. Consolidate every 10 entries: remove outdated, merge similar
5. Not a gate — never blocks execution. Informational input only.
6. Commit or gitignore: user decides (team vs personal scope)
