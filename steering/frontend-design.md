# Frontend Design Conventions

> This file is configurable. Edit to match your project's stack and design system.

## Design System Source

The active design system lives in `.interface-design/system.md`.
**Read it before generating any UI code.** Do not generate UI without it.
If it doesn't exist, create it with minimum tokens before proceeding.

## Stack

Configure for your project:
- **Components**: React | Vue | Svelte | (set yours)
- **Styling**: Tailwind CSS | CSS Modules | Styled Components | (set yours)
- **UI Library**: shadcn/ui | Radix UI | Headless UI | (set yours)
- **Icons**: Lucide | Heroicons | Phosphor | (set yours)

## Token Conventions (defaults — override in system.md)

```
spacing:    4px base → 4, 8, 12, 16, 24, 32, 48, 64
colors:     primary, secondary, surface, border, text, error, warning, success
radius:     sm(4px), md(8px), lg(16px), full(9999px)
shadow:     none, sm, md, lg
typography: sm(12), base(14), md(16), lg(18), xl(24), 2xl(32)
```

## Scope

This design system applies to:
- Dashboards and admin panels
- Internal tools and data-heavy apps

Does NOT apply to:
- Marketing / landing pages (no system.md enforcement)
- Email templates
- Native mobile

## UI Task Gate

Any task that generates UI code MUST:
1. Read `.interface-design/system.md` first
2. Use only tokens defined there
3. Register new design decisions in `system.md` AND `DECISIONS.md`

Code that contradicts `system.md` is BLOCKED until corrected.

## Visual Gate

UI tasks MUST pass Playwright MCP gate before being marked DONE.
See `steering/visual-automation.md` for configuration.
