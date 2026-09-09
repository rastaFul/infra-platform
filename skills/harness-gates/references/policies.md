# Hard Policies

Policies are rules the agent CANNOT violate, regardless of what is requested.

## Infrastructure Policies

### Cloud
- NEVER create security group with ingress 0.0.0.0/0 (except explicitly approved public ALB)
- NEVER remove stateful resources (databases, storage) without confirmed backup
- NEVER create resources without mandatory tags: `Environment`, `Team`, `App`
- NEVER use static credentials — use IAM roles or workload identity
- NEVER create public storage buckets
- NEVER disable encryption at rest

### Kubernetes
- NEVER deploy to production without passing in staging
- NEVER use `latest` as image tag
- NEVER create pod without resource limits
- NEVER create pod without health checks (liveness + readiness)
- NEVER expose service without TLS

### Terraform
- NEVER run `terraform destroy` without explicit approval
- NEVER run `terraform apply` without `terraform plan` first
- NEVER commit state file

### Secrets
- NEVER log passwords, tokens, API keys, PII
- NEVER commit secrets in code
- NEVER create secrets in plaintext — use a secrets manager

## Development Policies

### Code
- NEVER push directly to main/master
- NEVER remove existing tests without approval
- NEVER use `npm install` — always `npm ci`
- NEVER use `console.log/error` — use structured logger
- NEVER do empty catch or throw string

### Gates — TypeScript/Node.js

**Per-step gates** (run after each task):

| Gate | Command | PASS criteria |
|------|---------|---------------|
| TypeScript | `npx tsc --noEmit` | Exit code 0 |
| ESLint | `npm run lint` | 0 errors |
| Tests | `npm test` | All pass |

**Checkpoint gates** (every 3 tasks):

| Gate | Command | PASS criteria |
|------|---------|---------------|
| Coverage | `npm run test:coverage` | Above project threshold |
| npm audit | `npm audit --audit-level=high` | 0 critical + 0 high |

**Final gates** (after all tasks):

| Gate | Command | PASS criteria |
|------|---------|---------------|
| SonarQube | `sonar-scan` | Quality gate PASS |

### Deploy
- NEVER deploy without lint passing
- NEVER deploy without tests passing
- NEVER deploy with critical vulnerabilities
