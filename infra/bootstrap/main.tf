# One-time setup, run by hand with local state:
#   - S3 bucket for the main Terraform state
#   - GitHub OIDC deploy role for the pipeline

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "ap-south-1"
  default_tags {
    tags = { Project = "tenzin-a2" }
  }
}

variable "github_repo" {
  default = "Eyemusican/dso303-assignment2"
}

# the OIDC provider is shared by the whole AWS account, so another student may have made it already.
# false = use the existing one, true = create it
variable "create_oidc_provider" {
  type    = bool
  default = false
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ---------- state bucket ----------

resource "aws_s3_bucket" "tfstate" {
  bucket = "tenzin-a2-tfstate-${local.account_id}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- GitHub OIDC ----------

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# only pushes to main of my repo can assume this role
resource "aws_iam_role" "deploy" {
  name = "tenzin-a2-github-deploy-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
}

# Terraform has to create many kinds of resources, so some services need "*".
# Where the ARN has a name in it, access is limited to tenzin-a2-* names.
resource "aws_iam_role_policy" "deploy" {
  name = "tenzin-a2-deploy-access"
  role = aws_iam_role.deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "NetworkComputeCdn"
        Effect = "Allow"
        Action = [
          "ec2:*",
          "elasticloadbalancing:*",
          "ecs:*",
          "rds:*",
          "cloudfront:*",
          "ecr:GetAuthorizationToken",
          "logs:DescribeLogGroups",
          "lambda:CreateEventSourceMapping",
          "lambda:GetEventSourceMapping",
          "lambda:UpdateEventSourceMapping",
          "lambda:DeleteEventSourceMapping",
          "lambda:ListEventSourceMappings",
          "lambda:TagResource",
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "OwnS3Buckets"
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::tenzin-a2-*",
          "arn:aws:s3:::tenzin-a2-*/*"
        ]
      },
      {
        Sid      = "OwnEcr"
        Effect   = "Allow"
        Action   = "ecr:*"
        Resource = "arn:aws:ecr:ap-south-1:${local.account_id}:repository/tenzin-a2-*"
      },
      {
        Sid      = "OwnQueues"
        Effect   = "Allow"
        Action   = "sqs:*"
        Resource = "arn:aws:sqs:ap-south-1:${local.account_id}:tenzin-a2-*"
      },
      {
        Sid      = "OwnLambda"
        Effect   = "Allow"
        Action   = "lambda:*"
        Resource = "arn:aws:lambda:ap-south-1:${local.account_id}:function:tenzin-a2-*"
      },
      {
        Sid      = "OwnSecrets"
        Effect   = "Allow"
        Action   = "secretsmanager:*"
        Resource = "arn:aws:secretsmanager:ap-south-1:${local.account_id}:secret:tenzin-a2-*"
      },
      {
        Sid    = "OwnLogGroups"
        Effect = "Allow"
        Action = "logs:*"
        Resource = [
          "arn:aws:logs:ap-south-1:${local.account_id}:log-group:/ecs/tenzin-a2-*",
          "arn:aws:logs:ap-south-1:${local.account_id}:log-group:/aws/lambda/tenzin-a2-*"
        ]
      },
      {
        Sid    = "OwnIamRoles"
        Effect = "Allow"
        Action = "iam:*"
        Resource = [
          "arn:aws:iam::${local.account_id}:role/tenzin-a2-*"
        ]
      },
      {
        # the pipeline must not be able to give itself more permissions
        Sid      = "NotThisRole"
        Effect   = "Deny"
        Action   = "iam:*"
        Resource = "arn:aws:iam::${local.account_id}:role/tenzin-a2-github-deploy-role"
      }
    ]
  })
}

output "state_bucket" {
  value = aws_s3_bucket.tfstate.id
}

output "deploy_role_arn" {
  value = aws_iam_role.deploy.arn
}
