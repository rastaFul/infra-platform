# Terraform Modules Reference

All modules live in `terraform/modules/`. Each module has a consistent interface: `variables.tf`, `main.tf`, `outputs.tf`.

## Module Catalog

### `vpc/`
Creates an isolated VPC per project environment.

Inputs:
- `project` — project name (e.g., `vetcare`)
- `environment` — `staging` | `production`
- `cidr_block` — VPC CIDR (e.g., `10.10.0.0/16`)

Outputs: `vpc_id`, `public_subnet_ids`, `private_subnet_ids`

---

### `ecs-service/`
Deploys a containerized service to ECS Fargate.

Inputs:
- `project`, `environment`, `service_name`
- `image` — ECR image URI
- `cpu`, `memory` — Fargate task sizing
- `port` — container port
- `environment_vars` — map of env vars
- `secrets` — map of Vault secret paths (fetched at task start)
- `desired_count` — number of replicas

Outputs: `task_definition_arn`, `service_name`, `alb_dns_name`

---

### `ecr/`
Creates an ECR repository for a project service.

Inputs:
- `project`, `service_name`
- `image_retention_count` — keep N most recent images (default: 10)

Outputs: `repository_url`, `repository_arn`

---

### `rds-postgres/`
Creates an RDS PostgreSQL instance in private subnets.

Inputs:
- `project`, `environment`
- `instance_class` — e.g., `db.t3.micro`
- `db_name`, `db_username`
- `vpc_id`, `private_subnet_ids`
- `allowed_security_group_ids` — ECS task SGs

Outputs: `endpoint`, `port`, `db_name`

---

### `cloudflare-dns/`
Manages DNS records and optional Tunnel configuration for a service.

Inputs:
- `zone_id` — Cloudflare zone ID
- `hostname` — e.g., `api.vetcare.rastaful.dev`
- `origin` — ALB DNS name, Fly.io hostname, or Tunnel ID
- `proxied` — enable Cloudflare proxy (default: `true`)

Outputs: `record_id`, `fqdn`

---

### `k8s-service/`
Reserved for Phase 2 — Kubernetes deployment (EKS or GKE).

Placeholder. Implements same interface as `ecs-service/` for future migration path.

---

## Environments

| File | Purpose |
|------|---------|
| `environments/local.tfvars` | Local dev variables (no real infra) |
| `environments/staging.tfvars` | AWS staging account |
| `environments/production.tfvars` | AWS production account |

Usage:
```bash
terraform plan -var-file=environments/staging.tfvars
terraform apply -var-file=environments/production.tfvars
```
