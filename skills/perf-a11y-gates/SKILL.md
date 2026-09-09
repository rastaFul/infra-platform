# Perf/A11y Gates — Lighthouse CI + axe-core

Closes gap #12 from the 2026-09 gate audit: Playwright MCP (`skills/playwright-mcp`) covers functional E2E and `ux-journey-judge` covers goal-completion usability — neither measures performance or accessibility. Zero cost to add given Playwright is already in the flow for any visual-output task.

## Tools

- **Lighthouse CI** (`@lhci/cli`) — performance, best-practices, SEO score against a running local build.
- **axe-core** via `@axe-core/playwright` — accessibility violations (WCAG), injected into the SAME Playwright session already used for the E2E gate — no separate browser session needed.

## Usage

```bash
# Lighthouse — needs the app running locally (same precondition as playwright-mcp: curl -sf http://localhost:PORT)
bash skills/perf-a11y-gates/scripts/run-lighthouse.sh http://localhost:3000

# axe — meant to be called from WITHIN the existing Playwright E2E test, not standalone:
# see scripts/axe-snippet.md for the exact injection point in an existing playwright-mcp flow
```

## PASS criteria — DECIDED (QUESTIONS.pt-BR.md #2, 2026-09)

Minimum **90/100 on all 4 categories** (performance, accessibility, best-practices, SEO) — Google's own documented "green" band for Lighthouse scoring (90-100 = green, 50-89 = orange, 0-49 = red). This is the de-facto market bar for "good" quality, not an invented number. Any category below 90 fails the gate. Override per-project via env vars `LH_MIN_PERFORMANCE`/`LH_MIN_ACCESSIBILITY`/`LH_MIN_BEST_PRACTICES`/`LH_MIN_SEO` if a project has a documented reason to differ (default stays 90).

axe-core violations DO fail by default at `critical`/`serious` impact level — that's the tool's own sane default (not a business threshold), kept as-is.

## Where this plugs into the flow

- Activates under the same condition as the Playwright gate (`steering/visual-automation.md`): any task with visual/UI output.
- Runs AFTER the functional Playwright gate passes (no point measuring performance of a broken page) — same session, same browser instance, minimal extra cost.
- Same scripts in `.github/workflows/gates.yml` for any PR touching frontend paths.

## Setup

`npm install -g @lhci/cli` and `@axe-core/playwright` as a devDependency of the target project (added by `install.sh` alongside the existing `@playwright/mcp` install step).
