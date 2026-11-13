terraform {
  required_version = ">= 1.10"

  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    archive = { source = "hashicorp/archive", version = "~> 2.6" }
  }

  # bucket is passed in at init time: -backend-config="bucket=tenzin-a2-tfstate-<account id>"
  backend "s3" {
    key          = "assignment2/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = { Project = "tenzin-a2" }
  }
}

data "aws_caller_identity" "current" {}
