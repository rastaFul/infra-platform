# Tutorial 03 — First AWS Deploy (ECS Fargate)

**Goal:** Deploy a project service to AWS ECS Fargate using the Terraform modules.

**Time:** ~45 minutes

**Prerequisites:**
- AWS CLI configured (`aws configure`)
- Terraform >= 1.6 installed
- Docker image pushed to ECR
- Tutorial 01 complete (local platform running, Vault initialized)

---

## Step 1 — Initialize Terraform

```bash
cd ~/projects/infra-platform/terraform

# Initialize with staging variables
terraform init
terraform workspace new staging
terraform workspace select staging
```

---

## Step 2 — Create ECR repository

```bash
# Using the ecr module (example main.tf snippet):
module "ecr_vetcare_api" {
  source       = "./modules/ecr"
  project      = "vetcare"
  service_name = "api"
}
```

```bash
terraform plan -var-file=environments/staging.tfvars -target=module.ecr_vetcare_api
terraform apply -var-file=environments/staging.tfvars -target=module.ecr_vetcare_api
```

---

## Step 3 — Push Docker image

```bash
# Get ECR URI from Terraform output
ECR_URI=$(terraform output -raw ecr_vetcare_api_url)

# Build and push
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin "${ECR_URI}"

docker build -t vetcare-api ~/projects/vetcare
docker tag vetcare-api:latest "${ECR_URI}:latest"
docker push "${ECR_URI}:latest"
```

---

## Step 4 — Deploy VPC and ECS service

```bash
# Apply full staging environment
terraform plan -var-file=environments/staging.tfvars
terraform apply -var-file=environments/staging.tfvars
```

Terraform creates:
- VPC with public/private subnets
- ECS Fargate cluster and service
- ALB with target group and health check
- Security groups

---

## Step 5 — Configure DNS via Cloudflare

After ALB is provisioned:

```bash
# Get ALB DNS from Terraform output
ALB_DNS=$(terraform output -raw vetcare_api_alb_dns)

# Update cloudflare-dns module with ALB origin
# Edit terraform/main.tf:
module "dns_vetcare_api" {
  source   = "./modules/cloudflare-dns"
  zone_id  = var.cloudflare_zone_id
  hostname = "api.vetcare.rastaful.dev"
  origin   = ALB_DNS
  proxied  = true
}

terraform apply -var-file=environments/staging.tfvars -target=module.dns_vetcare_api
```

---

## Step 6 — Verify

```bash
# Health check via Cloudflare
curl https://api.vetcare.rastaful.dev/health | jq .

# Check ECS task logs
aws logs tail /ecs/vetcare-api --follow

# Check metrics in Grafana
# Grafana → Dashboards → Golden Signals → service=vetcare-api
```

---

## Rollback

If the deploy fails: see [How-To: Rollback Deployment](../how-to/rollback-deployment.md).

## Next Steps

- [How-To: Rotate a Vault Secret](../how-to/rotate-vault-secret.md)
- [How-To: Scale an ECS Service](../how-to/scale-ecs-service.md)
- [Explanation: Multi-Cloud Strategy](../explanation/multi-cloud-strategy.md)
