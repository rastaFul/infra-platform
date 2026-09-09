/**
 * lint-staged config — the fast pre-commit gate (husky + lint-staged).
 * Keep this FAST: heavy gates (dependency-cruiser, jscpd, Stryker) belong in
 * run-final.sh / CI, not here — pre-commit must not become a multi-minute
 * wait or developers will start using --no-verify.
 */
module.exports = {
  '*.{ts,tsx}': ['eslint --fix'],
  // tsc has no meaningful "only these files" mode for type-checking a
  // TS project, so this ignores the staged file list and runs a full
  // project check once per commit.
  '*.{ts,tsx,js,jsx}': () => 'tsc --noEmit',
};
