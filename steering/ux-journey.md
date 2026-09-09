# UX Journey — Goal-Oriented Usability Gate

> Configurable. Edit thresholds, classification rules, and score weights to match your project.

## What this gate answers

Not "does the flow work" (Playwright MCP already answers that) but: **given a goal and a starting state, can a user who has never seen the implementation discover how to reach it on their own?**

## Classification — when a UX Journey is mandatory

Every task that trips the existing UI trigger (component, page, layout, form, modal, table, dashboard, ...) gets classified:

| Tier | Definition | Journey required? |
|------|-----------|-------------------|
| TRIVIAL | Visual-only change to an existing screen: color, spacing, typography, copy, icon swap, token change. No new interactive element, no new route, no change to the steps a user takes or to what they see after acting. | No — `interface-design` + Playwright functional gate only (unchanged) |
| SIGNIFICANT | Anything that adds/removes/reorders a step the user takes, or changes what the user sees/understands after acting: new screen/route, new form, new modal/dialog flow, navigation change, onboarding change, state-changing action (create/update/delete/pay/submit), new error or empty state. | Yes — full flow below |

Rule of thumb: if you can describe the change purely in CSS/token terms, it's TRIVIAL. If describing it requires a verb the user performs ("user can now...", "user is redirected to...", "user sees a new confirmation..."), it's SIGNIFICANT.

When unsure, treat as SIGNIFICANT — the cost of an unnecessary journey is small; the cost of a silent regression is the retrabalho this gate exists to prevent.

## Flow

```
spec → classify → [SIGNIFICANT] journey.md → approval → TDD Red → implement
     → Playwright functional gate (PASS) → ux-journey-judge (PASS) → register → DONE
```

`ux-journey-judge` never runs before the Playwright functional gate passes — no point evaluating usability of a flow that's still broken.

## Authoring `journey.md`

Created via `bash skills/spec-manager/scripts/create-journey.sh <project-dir> <feature-name> <goal>`. Lives at `.specs/features/[feature]/journey.md`, sibling to `spec.md`.

Fixed section headings — do not rename them, `extract-journey-brief.sh` matches on exact headings:

```
## Actor
## Goal
## Starting State
## Entry Points
## Success Criteria
## Happy Path
## Failure Paths
## Recovery Expectations
## Friction Budget
## Hard Failure Notes
```

- **Success Criteria** must be observable, not adjectives. "Interface deve ser intuitiva" is not a criterion. "O usuário consegue identificar que a assinatura foi criada sem navegar para outra página" is.
- **Happy Path** is for the spec/task-executor's own reference (and for a human reviewer to sanity-check the journey is achievable at all) — it is NEVER shown to `ux-journey-judge`. See `extract-journey-brief.sh`.
- **Entry Points** are valid starting URLs/screens, not instructions — "dashboard, pricing page" is fine, "click Settings then Billing" is not.

## Friction Budget — defaults (override per journey)

```
wrong_actions: 1
backtracks:    1
dead_ends:     0
```

If the journey is destructive/irreversible/financial (delete, pay, cancel subscription, send irreversible message), default `wrong_actions: 0` — any wrong action on a destructive flow is itself a near-miss worth failing on.

## Hard Failures — not averaged away

Any one of these fails the journey regardless of score:

1. Goal not completed (`goal_completion < 1.0`)
2. Dead end — no visible way forward and no way back
3. Error encountered with no recovery path
4. Critical/destructive action proceeds without confirmation or undo
5. Success occurs but is not perceivable/understandable to the user
6. Blocking error with no explanation
7. Reaching the goal requires knowledge not available in the UI (external docs, tribal knowledge)
8. A required CTA is not discoverable within the journey's friction budget

## Score — diagnostic, never gating

```
Goal completion        gate (binary, see Hard Failures) — not part of the weighted score
Discoverability         35%   (finding entry point + CTAs; folds in accessible-name/role quality
                                observed via the accessibility tree — this is exploration signal,
                                not a WCAG audit)
Cognitive load          25%   (steps required vs. necessary, clarity of "what do I do next")
Feedback & status       25%   (does the UI communicate state, progress, success/failure)
Error recovery          10%
Consistency             5%    (same action labeled/behaving the same way across the journey)
```

The score is written to metrics for trend tracking. **It never overrides a hard failure or `goal_completion < 1.0`.** A 95/100 score with an unreached goal is still FAIL.

## Feedback routing (FAIL → next step)

`ux-journey-judge` returns `affected_step` + `suggested_direction`, not a fix. The orchestrator decides:

- Finding names a broken/missing UI element that should exist per spec → **implementation bug** → re-delegate to `task-executor` with the specific finding, same retry budget as other gates (`feedback-loop`, max 5).
- Finding says the flow works but is not discoverable/understandable as specced → **UX gap** → this is new information about the spec itself, not a code bug. Update spec/journey with the user (or escalate if it recurs after a fix attempt), don't just retry blindly.
- Same UX failure survives 2 fix attempts → escalate (`skills/harness-gates/references/escalation.md` format) — a third blind retry is exactly the "retry without learning" pattern this gate exists to avoid.

## Quick Mode

Quick mode skips spec/journey approval, never the gate. If a quick-mode change classifies SIGNIFICANT:
1. Implement as usual.
2. As part of the retrospec step, author `journey.md` retroactively from the user's original request (`create-journey.sh`, run after `create-retrospec.sh`) — goal/success criteria only need to reflect what was actually asked for.
3. Run `ux-journey-judge` exactly as in normal mode. FAIL blocks `Status: COMPLETED` the same as normal mode — quick mode shortens spec ceremony, not quality gates.

## Independence

`ux-journey-judge` is a separate sub-agent, spawned fresh via `Task` (no shared context with the orchestrator or `task-executor`). It receives ONLY the output of `extract-journey-brief.sh` (never the raw `journey.md`, never file paths, never route/selector names) plus the base URL and any starting-state setup the orchestrator already performed (e.g., a logged-in session). It has no code-reading tools. See the `ux-journey-judge` agent definition for its full protocol.

Not a UX gate:
- Design token conformance → `interface-design`
- Element/interaction works → `playwright-mcp` (functional E2E)
- Engineering quality → `harness-judge`

`ux-journey-judge` only answers: can a goal-driven, implementation-blind user complete this?
