# Code Gates

Scripts to run TypeScript/Node.js quality gates and return structured JSON results.

## Usage

### Per-step gates (fast, ~3s)
```bash
bash skills/code-gates/scripts/run-gates.sh [project-dir]
```
Runs: tsc → eslint → jest. Returns JSON.

### Checkpoint gates (every 3 tasks)
```bash
bash skills/code-gates/scripts/run-checkpoint.sh [project-dir]
```
Runs: coverage → npm audit. Returns JSON.

### Final gates (after all tasks)
```bash
bash skills/code-gates/scripts/run-final.sh [project-dir]
```
Runs: tsc → eslint → jest → coverage → npm audit → sonar-scan. Returns JSON.

### Architecture gate (final gate, or on demand)
```bash
bash skills/code-gates/scripts/run-architecture-gate.sh [project-dir] [src-dir]
```
Runs: dependency-cruiser against `.dependency-cruiser.cjs`. Returns JSON. `SKIPPED` if the config or `src/` (default `src-dir`) is missing.

### Quality-extra gate (final gate, or on demand)
```bash
bash skills/code-gates/scripts/run-quality-extra.sh [project-dir]
```
Runs: jscpd (duplication) + eslint filtered to `sonarjs/*` rules (cognitive complexity). Returns JSON. `SKIPPED` per-gate if the relevant config is missing.

### Mutation gate (final gate ONLY — slow)
```bash
bash skills/code-gates/scripts/run-mutation.sh [project-dir]
```
Runs: Stryker Mutator against `stryker.conf.json`. Returns JSON with `mutationScore`. `SKIPPED` if the config is missing. See "Mutation testing" below for why no score threshold is enforced yet.

## Output Format

```json
{
  "timestamp": "2026-01-01T12:00:00-03:00",
  "gates": {
    "tsc": {"status": "PASS", "errors": 0},
    "eslint": {"status": "PASS", "errors": 0, "warnings": 2},
    "jest": {"status": "PASS", "total": 27, "passed": 27, "failed": 0},
    "coverage": {"status": "PASS", "statements": 95, "branches": 88},
    "audit": {"status": "PASS", "critical": 0, "high": 0},
    "sonar": {"status": "SKIPPED"},
    "depcruise": {"status": "PASS", "errors": 0, "warnings": 0},
    "jscpd": {"status": "PASS", "clones": 0, "percentage": 0},
    "sonarjs_complexity": {"status": "PASS", "violations": 0},
    "stryker": {"status": "PASS", "mutationScore": 0}
  },
  "overall": "PASS"
}
```
`depcruise`/`jscpd`/`sonarjs_complexity`/`stryker` are produced by the three scripts above, not `run-gates.sh`/`run-checkpoint.sh`/`run-final.sh` — `run-final.sh` was NOT modified by this change (out of scope for the task that added these gates); wiring them into `run-final.sh`'s merge is a follow-up, run them standalone until then.

## Dev quality gates — dependency-cruiser, sonarjs, jscpd, Stryker, husky

Five tools, each closing a specific gap: architecture rules were prose only, complexity/duplication were unmeasured, test quality was tracked by coverage % alone (which mutation testing exists specifically to catch — e.g. a test that calls a function but asserts nothing still counts as "covered"), and nothing ran before a commit existed (everything was post-hoc, after-the-fact gates).

### dependency-cruiser — architecture conformance

Translates the prose rules in `steering/architecture.md` and `steering/service-layers.md` into an executable ruleset: `templates/dev-quality/.dependency-cruiser.cjs`. Each rule's `comment` field quotes the steering-doc line it enforces (domain zero external deps, application never imports infrastructure, handler never imports infrastructure directly, etc). Assumes the `src/domain|application|infrastructure|interface` layout from `architecture.md`; edit the `path` regexes if a project's layout differs — it's a copied template, not a fixed contract.

Run via `run-architecture-gate.sh` (see above).

### eslint-plugin-sonarjs — cognitive complexity

Not a separate CLI — it's an ESLint plugin. Add it to the target project's own ESLint config (flat config example):
```js
const sonarjs = require('eslint-plugin-sonarjs');
module.exports = [
  // ...existing config
  {
    plugins: { sonarjs },
    rules: {
      ...sonarjs.configs.recommended.rules,
    },
  },
];
```
Once wired in, `npm run lint` (run-gates.sh's `eslint` gate) already enforces it as part of the normal lint error count. `run-quality-extra.sh` additionally runs its own `eslint --format json` pass and reports `sonarjs/*` violations as a separate `sonarjs_complexity` count, distinct from general lint noise — useful when triaging (a `sonarjs/cognitive-complexity` violation means "restructure this function," not "fix a typo").

### jscpd — copy-paste / duplication detection

Config: `templates/dev-quality/.jscpd.json`. No duplication-percentage threshold is set (jscpd's own default: report only, does not fail the build) — no historical duplication baseline exists yet to justify a business threshold, see Constraints in the originating spec. `run-quality-extra.sh`'s `jscpd` gate status reflects jscpd's own exit code, so once a `threshold` value is added to the config, PASS/FAIL will start reflecting it with no script change.

### Stryker Mutator — mutation testing

Config: `templates/dev-quality/stryker.conf.json`. Mutates `src/domain/**` and `src/application/**` only (business logic — steering/testing.md's ≥80% coverage target layers) — mutating `infrastructure/`/`interface/` adapters is generally low signal. `thresholds.break` is `null` (Stryker's own scaffold default, not a build-breaking gate) because no mutation-score baseline exists yet; `thresholds.high`/`low` (80/60) are cosmetic report-coloring bands only, loosely tracking `steering/testing.md`'s coverage targets but not enforced. Run via `run-mutation.sh` — final gate only, this is slow (re-runs the suite per surviving mutant).

### husky + lint-staged + commitlint — local pre-commit gate

Everything else in this file runs post-hoc (after code exists). This is the only gate that runs before a commit is created.
- `templates/dev-quality/lint-staged.config.cjs` — `eslint --fix` on staged `.ts`/`.tsx`, full-project `tsc --noEmit` (kept fast: no dependency-cruiser/jscpd/Stryker in pre-commit, those stay in the final gate / CI).
- `templates/dev-quality/commitlint.config.cjs` — Conventional Commits (`@commitlint/config-conventional`).
- `templates/dev-quality/husky/{pre-commit,commit-msg}` — hook scripts; `husky/setup-husky.sh` runs `npx husky init` and installs them, plus copies the other four config files to the target project root.

Setup, from the target project root, after `install.sh` has copied `templates/`:
```bash
npm install -D husky lint-staged @commitlint/cli @commitlint/config-conventional dependency-cruiser eslint-plugin-sonarjs jscpd @stryker-mutator/core @stryker-mutator/jest-runner
bash templates/dev-quality/husky/setup-husky.sh
```
`install.sh` copies the template files into the target project's `templates/dev-quality/` but does NOT run `npm install` or `setup-husky.sh` automatically — that decision (auto-run vs. document-only) was left open, see project QUESTIONS.
