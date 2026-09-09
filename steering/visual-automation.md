# Visual Automation — Playwright MCP

> Configure thresholds and scope to match your project.

## MCP Server

```bash
npx @playwright/mcp@latest
```

50+ browser automation tools exposed to Claude via MCP.
Used for E2E tests, visual regression, and UI gate validation.

## Test File Structure

```
e2e/
├── flows/          # User journey tests (happy path + error path)
│   └── [feature].spec.ts
└── visual/         # Component snapshot and regression tests
    └── [component].spec.ts
```

## Screenshot Baseline

- Location: `.specs/features/[feature]/screenshots/`
- First run: creates baseline (no comparison)
- Subsequent runs: compare against baseline
- **Diff threshold: 5%** — above this = FAIL, require human approval to update

## Gate Rules

```
WRITE TEST (Red) → IMPLEMENT → RUN GATE → PASS → register → task DONE
                                         → FAIL → fix → re-run (max 5)
```

1. E2E test written BEFORE implementation (TDD Red — must fail first)
2. Gate runs AFTER implementation
3. Result registered in `.specs/audit/execution.md` with timestamp
4. Task is NOT complete until gate PASSES

## Coverage Targets

| Flow type | Target |
|-----------|--------|
| Critical user flows (login, CRUD primary entity) | 100% |
| Secondary flows | 60% |
| Error paths | as defined in spec |

## When NOT to Use Playwright

- Unit and integration testing → Jest
- API endpoint testing → Supertest / curl
- Backend, infra, script tasks
- TDD Red phase (tests expected to fail — not a gate failure)

## App Server Requirement

Always verify app is running before invoking Playwright gate:
```bash
curl -sf http://localhost:3000 > /dev/null || echo "Server not running"
```
