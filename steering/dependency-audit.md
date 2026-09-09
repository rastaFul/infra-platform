# Dependency Audit

## When to Audit

- Before any new dependency is added
- During checkpoint gates (npm audit)
- When updating dependencies

## Criteria for Adding Dependencies

1. **Is it necessary?** Can the functionality be achieved with stdlib or existing deps?
2. **Is it maintained?** Last commit < 6 months, active issues/PRs
3. **Is it secure?** No known critical vulnerabilities
4. **Is it lightweight?** Check bundle size impact
5. **Is it well-typed?** Has TypeScript types (built-in or @types/)

## npm audit Rules

- 0 critical vulnerabilities: MANDATORY
- 0 high vulnerabilities: MANDATORY
- Moderate/low: acceptable but track

## Outdated Dependencies

- Major versions behind: flag as WARN
- Security patches available: flag as CRITICAL
- Run `npm outdated` at checkpoints

## Lock File

- Always commit package-lock.json
- Always use `npm ci` (never `npm install` in CI/agents)
- Review lock file changes in PRs
