# ECR, ALB and the ECS Fargate service that runs the API

resource "aws_ecr_repository" "api" {
  name         = "${var.prefix}-api"
  force_delete = true
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_lb" "api" {
  name               = "${var.prefix}-alb"
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "api" {
  name        = "${var.prefix}-api-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path    = "/health"
    matcher = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.prefix}-api"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "main" {
  name = "${var.prefix}-cluster"
}

# execution role: lets ECS pull the image and write logs
resource "aws_iam_role" "ecs_execution" {
  name = "${var.prefix}-ecs-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# task role: what the API code itself may do
resource "aws_iam_role" "ecs_task" {
  name               = "${var.prefix}-ecs-task-role"
  assume_role_policy = aws_iam_role.ecs_execution.assume_role_policy
}

resource "aws_iam_role_policy" "ecs_task" {
  name = "${var.prefix}-api-access"
  role = aws_iam_role.ecs_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.db.arn
      },
      {
        # presigned POSTs are signed with this role, so it needs PutObject
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.assignments.arn}/assignments/*"
      }
    ]
  })
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.prefix}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name         = "api"
    image        = "${aws_ecr_repository.api.repository_url}:${var.image_tag}"
    essential    = true
    portMappings = [{ containerPort = 8080 }]
    environment = [
      { name = "AWS_REGION", value = var.region },
      { name = "DB_HOST", value = aws_db_instance.main.address },
      { name = "DB_NAME", value = aws_db_instance.main.db_name },
      { name = "DB_USER", value = aws_db_instance.main.username },
      { name = "DB_SECRET_ARN", value = aws_secretsmanager_secret.db.arn },
      { name = "UPLOAD_BUCKET", value = aws_s3_bucket.assignments.id }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.api.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "api"
      }
    }
  }])
}

# 2 tasks, spread over the private app subnets in both AZs
resource "aws_ecs_service" "api" {
  name                              = "${var.prefix}-api"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.api.arn
  desired_count                     = 2
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = aws_subnet.app[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http, aws_secretsmanager_secret_version.db]
}
