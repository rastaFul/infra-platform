# Interface Design

Persistent design system guardian. Reads and writes `.interface-design/system.md` to maintain visual consistency across sessions. Source: https://github.com/Dammyjay93/interface-design

## Protocol

1. **Session start (UI task)**: Read `.interface-design/system.md` before generating any component
2. **If file missing**: Create it with minimum tokens from user's project description, confirm, record in DECISIONS.md
3. **New decision made**: Write to `system.md` AND `DECISIONS.md` in the same step
4. **UI code generated**: Verify it uses tokens from `system.md` — reject if it contradicts them

## Trigger

Activate when task involves: component, page, layout, form, modal, table, dashboard, color, spacing, typography, theme, token, design system.

Do NOT activate for: backend, API, database, infra, scripts, unit tests without UI.

## Files

| File | Access | Purpose |
|------|--------|---------|
| `.interface-design/system.md` | Read + Write | Design tokens, component patterns, visual rules |
| `steering/frontend-design.md` | Read | Project-level stack and conventions |
| `.specs/project/DECISIONS.md` | Write | Design decisions log |

## system.md Structure

```markdown
# Design System

## Tokens
- spacing: 4px base (4, 8, 12, 16, 24, 32, 48, 64)
- colors: primary, secondary, surface, border, text, error, warning, success
- radius: sm(4px) md(8px) lg(16px) full(9999px)
- shadow: none, sm, md, lg
- typography: sm(12) base(14) md(16) lg(18) xl(24) 2xl(32)

## Components
[document component decisions as they are made]

## Patterns
[document layout and interaction patterns]
```

## Rules

1. Never overwrite existing tokens without explicit user confirmation
2. Scope: dashboards, apps, tools, admin panels — not marketing pages
3. UI task gate: code that contradicts `system.md` is BLOCKED until fixed
4. Read `system.md` even in quick mode — no exceptions
