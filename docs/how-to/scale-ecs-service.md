# How-To: Scale an ECS Service

## Manual scaling (immediate)

```bash
aws ecs update-service \
  --cluster <project>-<environment> \
  --service <service-name> \
  --desired-count <N>

# Wait for stabilization
aws ecs wait services-stable \
  --cluster <project>-<environment> \
  --services <service-name>
echo "Scaled to ${N} tasks"
```

## Via Terraform (persistent)

```hcl
# In the ecs-service module call:
module "vetcare_api" {
  source        = "./modules/ecs-service"
  # ...
  desired_count = 3   # change from 1 to 3
}
```

```bash
terraform apply -var-file=environments/production.tfvars -target=module.vetcare_api
```

## Auto Scaling (Application Auto Scaling)

Add to the `ecs-service` module (Phase 1):

```hcl
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = 10
  min_capacity       = 1
  resource_id        = "service/${var.cluster_name}/${var.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.service_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}
```

## Monitor after scaling

```bash
# Watch task count
watch -n 5 'aws ecs describe-services \
  --cluster <project>-production \
  --services <service> \
  --query "services[0].{running:runningCount,desired:desiredCount,pending:pendingCount}"'
```
