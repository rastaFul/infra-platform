# UX Journey

Goal-oriented usability gate, independent from functional E2E (`playwright-mcp`), visual/token conformance (`interface-design`), and engineering quality (`harness-judge`). Answers one question: *given a goal and a starting state, can an implementation-blind user discover how to complete it?*

## Protocol

```
classify (TRIVIAL|SIGNIFICANT) → [SIGNIFICANT] journey.md before implementation → approval
  → TDD Red → implement → Playwright functional gate PASS → ux-journey-judge PASS → register → DONE
```

1. Classify visual impact per `steering/ux-journey.md` §Classification. Record it in `spec.md`.
2. If SIGNIFICANT: `bash skills/spec-manager/scripts/create-journey.sh <project-dir> <feature> "<goal>"`, fill in the sections, get it approved alongside the spec (skip approval only in quick mode).
3. Implement and pass the Playwright functional gate as usual — `ux-journey-judge` never runs against a functionally broken flow.
4. Extract the evaluator-safe brief: `bash skills/spec-manager/scripts/extract-journey-brief.sh <project-dir> <feature>` — this strips the `Happy Path` section (and anything else not on the whitelist). Never hand-paste from `journey.md` directly; always use the script, so implementation hints can't leak into the evaluator's prompt by accident.
5. Delegate to `ux-journey-judge` via `Task` with the extracted brief + base URL + any starting-state setup already done (e.g., logged-in session) as the entire prompt. Do not name routes, components, or files.
6. On PASS: register result, continue.
7. On FAIL: read `affected_step`/`suggested_direction`, route per `steering/ux-journey.md` §Feedback routing. Same retry ceiling as `feedback-loop` (max 5 for dev).
8. On BLOCKED: treat like a blocked `task-executor` return — resolve the blocker (app not running, missing seed data, ambiguous starting state) and retry.
9. Register: `bash skills/audit-writer/scripts/log-ux-result.sh <project-dir> <feature> <result-json>` — writes a `.specs/audit/execution.md` entry + a `.specs/metrics/*.ux.md` file.

## Trigger

Runs for any task already classified SIGNIFICANT under the existing UI trigger (component, page, layout, form, modal, table, dashboard, color, spacing, typography, theme, token, design system — same keywords as `interface-design`/`playwright-mcp`). TRIVIAL-classified UI tasks skip this skill entirely; other gates still apply.

## Files

| File | Access | Purpose |
|------|--------|---------|
| `.specs/features/[feature]/journey.md` | Write (orchestrator, via script) | Full journey definition — includes Happy Path, internal only |
| `.specs/features/[feature]/ux-evaluation.md` | Write (`ux-journey-judge` only) | Full evaluation report + findings |
| `.specs/features/[feature]/screenshots/ux/` | Write (`ux-journey-judge` only) | Evidence screenshots |
| `.specs/audit/execution.md` | Write (orchestrator, via script) | UX result line, chronological |
| `.specs/metrics/*.ux.md` | Write (orchestrator, via script) | Structured result for trend tracking |
| `steering/ux-journey.md` | Read | Classification rules, friction budget defaults, hard-failure list, score weights |

## Rules

1. Never invoke `ux-journey-judge` before the Playwright functional gate passes.
2. Never hand the evaluator the raw `journey.md`, a route, a selector, a component/file name, or the Happy Path section — only the extracted brief.
3. `goal_completion < 1.0` or any hard failure = FAIL, full stop. The weighted score never overrides this.
4. Do not run this gate for TRIVIAL-classified changes — that's scope creep the harness exists to avoid, not usability the harness exists to protect.
5. A UX FAIL blocks task DONE and blocks `Status: COMPLETED`, same as any other mandatory gate.
