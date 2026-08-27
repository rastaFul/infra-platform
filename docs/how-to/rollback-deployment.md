# How-To: Rollback a Deployment

## Docker Compose (local)

```bash
cd ~/projects/<project>/infra

# Roll back to previous image tag
docker compose pull  # or specify IMAGE_TAG in .env

# Restart with previous image
IMAGE_TAG=<previous-sha> docker compose up -d <service>
```

## ECS Fargate (AWS)

```bash
# List recent task definition revisions
aws ecs list-task-definitions --family <project>-<service> \
  --sort DESC --query 'taskDefinitionArns[0:5]'

# Update service to previous task definition revision
aws ecs update-service \
  --cluster <project>-staging \
  --service <service> \
  --task-definition <project>-<service>:<previous-revision> \
  --force-new-deployment

# Watch rollout
aws ecs wait services-stable \
  --cluster <project>-staging \
  --services <service>
echo "Rollback complete"
```

## Terraform state rollback

If a Terraform apply introduced bad infrastructure:

```bash
cd ~/projects/infra-platform/terraform

# See recent state changes
terraform show

# Target-destroy the bad resource
terraform destroy -target=<resource.name> -var-file=environments/staging.tfvars

# Or restore from state backup
terraform state pull > current.tfstate.backup
# (restore previous .tfstate from S3 backend or local backup)
```
