/**
 * commitlint config — enforces Conventional Commits on every commit message
 * via the .husky/commit-msg hook (see templates/dev-quality/husky/).
 */
module.exports = {
  extends: ['@commitlint/config-conventional'],
};
