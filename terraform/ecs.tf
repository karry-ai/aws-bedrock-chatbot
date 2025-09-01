locals {
  ecs = {
    cluster_name                        = "webui-bedrock-cluster"
    service_name_webui                  = "openwebui"
    service_name_bedrock_access_gateway = "bedrock-access-gateway"
    service_name_mcpo                   = "mcpo"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = local.ecs.cluster_name
}

resource "aws_ecs_cluster_capacity_providers" "ecs_cluster_capacity_provider" {
  cluster_name       = aws_ecs_cluster.ecs_cluster.name
  capacity_providers = ["FARGATE"]
}

# Application Load Balancer
module "alb_sg" {
  source = "./modules/security_group"

  name   = "alb-sg"
  vpc_id = aws_vpc.default.id

  cidr_egresses = [{
    cidr_blocks = [local.vpc_cidr]
    port        = 0
    protocol    = "-1"
  }]

  cidr_ingresses = [
    {
      cidr_blocks = ["0.0.0.0/0"]
      port        = 80
      protocol    = "tcp"
    },
    {
      cidr_blocks = ["0.0.0.0/0"]
      port        = 443
      protocol    = "tcp"
    }
  ]
}

resource "aws_lb" "alb" {
  name               = "webui-bedrock-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.alb_sg.id]
  subnets            = aws_subnet.public_subnets[*].id
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_target_group" "alb_target_group" {
  name        = "webui-bedrock-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 45
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

# Target group for MCPO service
resource "aws_lb_target_group" "mcpo_target_group" {
  name        = "mcpo-target-group"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.default.id
  target_type = "ip"

           health_check {
           path                = "/openapi.json"
           interval            = 300
           timeout             = 30
           healthy_threshold   = 2
           unhealthy_threshold = 10
           matcher             = "200-499"
         }
}

resource "aws_lb_listener_rule" "alb_listener_rule" {
  listener_arn = aws_lb_listener.alb_listener.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group.arn
  }

  condition {
    path_pattern {
      values = ["*"]
    }
  }
}

# Listener rule for MCPO service
resource "aws_lb_listener_rule" "mcpo_listener_rule" {
  listener_arn = aws_lb_listener.alb_listener.arn
  priority     = 100  # Lower priority number = higher precedence

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mcpo_target_group.arn
  }

  condition {
    path_pattern {
      values = [
        "/openapi.json",
        "/docs",
        "/time*",
        "/opensearch*",
        "/mcp/*"
      ]
    }
  }
}

# IAM Roles
data "aws_iam_policy_document" "task_execution_policy" {
  statement {
    actions   = ["logs:CreateLogGroup"]
    resources = ["arn:aws:logs:${var.region}:${var.account_id}:*"]
  }

  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.bag_api_key_secret.arn,
      aws_secretsmanager_secret.mcpo_api_key_secret.arn,

      aws_secretsmanager_secret.opensearch_mcp_api_key_secret.arn
    ]
  }

  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "task_execution_policy" {
  name_prefix = "task-execution-policy-"
  policy      = data.aws_iam_policy_document.task_execution_policy.json
}

module "task_execution_role" {
  source  = "./modules/iam_role"
  name    = "${local.ecs.cluster_name}-task-execution-role"
  service = ["ecs-tasks.amazonaws.com"]
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    aws_iam_policy.task_execution_policy.arn
  ]
}

data "aws_iam_policy_document" "bag_service_policy" {
  statement {
    actions   = ["bedrock:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "bag_service_policy" {
  name_prefix = "bag-service-policy-"
  policy      = data.aws_iam_policy_document.bag_service_policy.json
}

module "bag_service_role" {
  source              = "./modules/iam_role"
  name                = "${local.ecs.cluster_name}-bag-service-role"
  service             = ["ecs-tasks.amazonaws.com"]
  managed_policy_arns = [aws_iam_policy.bag_service_policy.arn]
}

# OPENWEBUI
## OpenWebUI ECS Service
module "ecs_service_openwebui_sg" {
  source = "./modules/security_group"

  name   = "${local.ecs.service_name_webui}-sg"
  vpc_id = aws_vpc.default.id

  cidr_egresses = [{
    cidr_blocks = ["0.0.0.0/0"]
    port        = 0
    protocol    = "-1"
  }]

  security_group_ingresses = [
    {
      security_groups = [module.alb_sg.id]
      port            = 8080
      protocol        = "tcp"
    }
  ]
}

resource "aws_ecs_task_definition" "task_definition_openwebui" {
  family                   = local.ecs.service_name_webui
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  memory                   = 4096
  cpu                      = 2048
  execution_role_arn       = module.task_execution_role.arn
  task_role_arn            = module.task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "openwebui"
      image     = "${aws_ecr_repository.openwebui_repository.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "OPENAI_API_BASE_URL"
          value = "http://gateway.bedrock.local/api/v1"
        },
        {
          name  = "MCP_SERVER_URL"
          value = "http://mcpo.bedrock.local"
        },
        {
          name  = "MCP_SERVER_NAME"
          value = "mcpo"
        }
      ]
      secrets = [
        {
          name      = "OPENAI_API_KEY"
          valueFrom = aws_secretsmanager_secret.bag_api_key_secret.arn
        },
        {
          name      = "MCP_SERVER_API_KEY"
          valueFrom = aws_secretsmanager_secret.mcpo_api_key_secret.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = "/ecs/${local.ecs.cluster_name}/openwebui"
          awslogs-region        = var.region
          awslogs-create-group  = "true"
          awslogs-stream-prefix = "ecs"
        }
      }
      mountPoints = [
        {
          sourceVolume  = "openwebui-efs-volume"
          containerPath = "/app/backend/data"
          readOnly      = false
        }
      ]
    }
  ])

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  volume {
    name = "openwebui-efs-volume"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.efs_filesystem.id
      root_directory     = "/"
      transit_encryption = "ENABLED"
    }
  }
}

resource "aws_ecs_service" "ecs_service_openwebui" {
  name                   = local.ecs.service_name_webui
  cluster                = aws_ecs_cluster.ecs_cluster.id
  task_definition        = aws_ecs_task_definition.task_definition_openwebui.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  force_new_deployment   = true
  enable_execute_command = true

  network_configuration {
    subnets          = aws_subnet.webui_private_subnets[*].id
    security_groups  = [module.ecs_service_openwebui_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.alb_target_group.arn
    container_name   = "openwebui"
    container_port   = 8080
  }
}

## OpenWebUI EFS
module "efs_sg" {
  source = "./modules/security_group"
  name   = "efs-sg"
  vpc_id = aws_vpc.default.id

  cidr_egresses = [{
    cidr_blocks = ["0.0.0.0/0"]
    port        = 0
    protocol    = "-1"
  }]

  security_group_ingresses = [
    {
      security_groups = [module.ecs_service_openwebui_sg.id]
      port            = 2049
      protocol        = "tcp"
    }
  ]
}

resource "aws_efs_file_system" "efs_filesystem" {
  creation_token  = "openwebui-efs"
  encrypted       = true
  throughput_mode = "elastic"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_archive = "AFTER_90_DAYS"
  }
}

resource "aws_efs_mount_target" "efs_mount" {
  count = length(aws_subnet.webui_private_subnets)

  file_system_id  = aws_efs_file_system.efs_filesystem.id
  subnet_id       = aws_subnet.webui_private_subnets[count.index].id
  security_groups = [module.efs_sg.id]
}

# MODULES FOR OPENWEBUI
module "ecs_service_module_sg" {
  source = "./modules/security_group"

  name   = "module-sg"
  vpc_id = aws_vpc.default.id

  cidr_egresses = [{
    cidr_blocks = ["0.0.0.0/0"]
    port        = 0
    protocol    = "-1"
  }]

  security_group_ingresses = [
    {
      security_groups = [module.ecs_service_openwebui_sg.id]
      port            = 80
      protocol        = "tcp"
    },
    # Allow ALB to reach mcpo on port 8000
    {
      security_groups = [module.alb_sg.id]   # ALB security group
      port            = 8000
      protocol        = "tcp"
    }
  ]

  
}

## Bedrock Access Gateway ECS Service
resource "aws_ecs_task_definition" "task_definition_bag" {
  family                   = local.ecs.service_name_bedrock_access_gateway
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  memory                   = 1024
  cpu                      = 512
  task_role_arn            = module.bag_service_role.arn
  execution_role_arn       = module.task_execution_role.arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "bedrock-access-gateway"
      image     = "${aws_ecr_repository.bag_repository.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      secrets = [
        {
          name      = "API_KEY"
          valueFrom = aws_secretsmanager_secret.bag_api_key_secret.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = "/ecs/${local.ecs.cluster_name}"
          awslogs-region        = var.region
          awslogs-create-group  = "true"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "ecs_service_bag" {
  name            = local.ecs.service_name_bedrock_access_gateway
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.task_definition_bag.arn

  desired_count        = 1
  launch_type          = "FARGATE"
  force_new_deployment = true

  network_configuration {
    subnets          = aws_subnet.module_private_subnets[*].id
    security_groups  = [module.ecs_service_module_sg.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.sd_discovery_service_bag.arn
  }
}

## MCPO ECS Service
resource "aws_ecs_task_definition" "task_definition_mcpo" {
  family                   = local.ecs.service_name_mcpo
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  memory                   = 1024
  cpu                      = 512
  execution_role_arn       = module.task_execution_role.arn
  task_role_arn            = module.task_execution_role.arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "mcpo"
      image     = "${aws_ecr_repository.mcpo_repository.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]
      secrets = [
        {
          name      = "API_KEY"
          valueFrom = aws_secretsmanager_secret.mcpo_api_key_secret.arn
        },
        
        {
          name      = "OPENSEARCH_MCP_API_KEY"
          valueFrom = aws_secretsmanager_secret.opensearch_mcp_api_key_secret.arn
        }
      ]
      environment = [
                  {
            name  = "OPENSEARCH_MCP_URL"
            value = var.opensearch_mcp_url
          },
                  {
          name  = "FORCE_UPDATE"
          value = "v28" // Force update for ALB routing fixes
        },
        {
          name  = "PORT"
          value = "8000"
        },

      ]
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = "/ecs/${local.ecs.cluster_name}"
          awslogs-region        = var.region
          awslogs-create-group  = "true"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
  

}

resource "aws_ecs_service" "ecs_service_mcpo" {
  name            = local.ecs.service_name_mcpo
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.task_definition_mcpo.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  platform_version = "LATEST"
  enable_execute_command = true

  health_check_grace_period_seconds = 600  // 10 minutes grace period for health checks

  network_configuration {
    subnets          = aws_subnet.webui_private_subnets[*].id
    security_groups  = [module.ecs_service_module_sg.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.sd_discovery_service_mcpo.arn
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.mcpo_target_group.arn
    container_name   = "mcpo"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.alb_listener]
}

# Service Discovery for Bedrock Access Gateway
resource "aws_service_discovery_private_dns_namespace" "sd_dns_namespace" {
  name = "bedrock.local"
  vpc  = aws_vpc.default.id
}

resource "aws_service_discovery_service" "sd_discovery_service_bag" {
  name = "gateway"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.sd_dns_namespace.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "sd_discovery_service_mcpo" {
  name = "mcpo"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.sd_dns_namespace.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
