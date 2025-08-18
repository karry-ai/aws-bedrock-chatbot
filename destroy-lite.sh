#!/bin/bash
set -euo pipefail

# Targeted destroy that removes costly resources while preserving EFS and ECR
# - Destroys: ECS services/cluster, ALB (listener, rule, target group), NAT/EIP,
#             Interface VPC Endpoints, EFS mount targets
# - Preserves: EFS filesystem (data), ECR repositories (images)

ROOT_DIR="/Users/shacharilan/Projects/aws-bedrock-chatbot"
cd "$ROOT_DIR/terraform"

terraform plan -destroy -out destroy-lite.tfplan \
  -target=aws_ecs_service.ecs_service_openwebui \
  -target=aws_ecs_service.ecs_service_bag \
  -target=aws_ecs_service.ecs_service_mcpo \
  -target=aws_ecs_cluster_capacity_providers.ecs_cluster_capacity_provider \
  -target=aws_ecs_cluster.ecs_cluster \
  -target=aws_lb_listener_rule.alb_listener_rule \
  -target=aws_lb_listener.alb_listener \
  -target=aws_lb_target_group.alb_target_group \
  -target=aws_lb.alb \
  -target=aws_nat_gateway.natgw \
  -target=aws_eip.eip \
  -target=module.vpc_interface_endpoints \
  -target=aws_efs_mount_target.efs_mount

echo "Plan saved to: $ROOT_DIR/terraform/destroy-lite.tfplan"
echo "Review the plan output above. To destroy exactly these resources, run:"
echo "    cd $ROOT_DIR/terraform && terraform apply \"destroy-lite.tfplan\""


