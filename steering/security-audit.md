# Security Audit

## Code Security Rules

- No hardcoded secrets (API keys, passwords, tokens)
- No SQL injection (use parameterized queries)
- No command injection (never interpolate user input into shell commands)
- No path traversal (validate and sanitize file paths)
- No XSS (sanitize output, use templating engines with auto-escape)
- No insecure deserialization

## Authentication & Authorization

- Never store passwords in plaintext (use bcrypt/argon2)
- JWT tokens: short expiry, refresh token rotation
- Always validate authorization on every request (not just authentication)
- Principle of least privilege for service accounts

## Data Protection

- Encrypt at rest (database, storage)
- Encrypt in transit (TLS everywhere)
- Never log PII (emails, phones, IDs, financial data)
- Mask sensitive data in error responses

## Dependencies

- No known critical/high vulnerabilities (npm audit)
- Pin exact versions in production
- Review new dependencies before adding

## Infrastructure

- No public storage buckets
- No overly permissive IAM policies
- No security groups with 0.0.0.0/0 ingress (except public load balancers)
- Secrets in a secrets manager, never in environment variables or code

## Scanning Tools

- `npm audit` — dependency vulnerabilities
- `tfsec` — Terraform security
- `checkov` — IaC compliance
- `trivy` — container vulnerabilities
- SonarQube — code security issues
