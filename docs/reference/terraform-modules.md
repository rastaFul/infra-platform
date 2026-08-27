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
Reserved for Phase 3 — Kubernetes deployment (EKS or GKE). See ADR 001 for trigger conditions.

Placeholder. Implements same interface as `ecs-service/` for future migration path.

---

### `oci-compute/` — NOT YET IMPLEMENTED (see `docs/how-to/provision-oracle-free-tier.md`)
Provisions the `oci-free` environment (ADR 007): VCN, subnet, security list (SSH only, no public app ports — Cloudflare Tunnel handles ingress), Ampere A1 Flex compute instance, boot volume, cloud-init bootstrap that installs Docker + Coolify.

Planned inputs:
- `region` — OCI region (prefer non-US, see how-to)
- `ocpus`, `memory_in_gbs` — instance shape sizing (2 OCPU / 12GB per ADR 007)
- `ssh_public_key` — for emergency access only (Coolify is the normal management path)

Planned outputs: `instance_public_ip`, `instance_id`

---

## Environments

Restructured 2026-08-27 (ADR 005) — one directory per environment, not per AWS-only stage:

| Environment | Directory | Cloud | Purpose |
|---|---|---|---|
| `local` | `environments/local/` | none (WSL2 Docker Compose) | Dev loop, all gates run here first |
| `oci-free` | `environments/oci-free/` | Oracle Cloud (Always Free) | First real cloud target, $0 cost — ADR 007 |
| `aws-prod` | `environments/production/` | AWS | Production, once justified by revenue |

State backend: **Terraform Cloud** (free tier) for every environment, cloud-agnostic — see ADR 008. Never a cloud-specific backend (e.g. S3), to keep state storage decoupled from whichever cloud is in use.

Usage:
```bash
terraform plan -var-file=environments/oci-free/terraform.tfvars
terraform apply -var-file=environments/production/terraform.tfvars
```
