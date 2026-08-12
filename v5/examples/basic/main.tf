# ─────────────────────────────────────────────────────────────────────────────
# Example 1: Basic — Simple 3-AZ Web Application VPC
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.69"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "../.."

  vpc = {
    name = "web-app-vpc"
  }

  addressing = {
    ipv4 = { cidr_block = "10.0.0.0/16" }
  }

  availability_zones = { count = 3 }

  subnets = {
    public = {
      role = "public"
      ipv4 = { netmask = 24 }
      routing = {
        internet_gateway = true
      }
      public_options = {
        map_public_ip = true
      }
    }

    app = {
      role = "private"
      ipv4 = { netmask = 22 }
      routing = {
        nat_gateway = true
      }
    }

    database = {
      role = "isolated"
      ipv4 = { netmask = 24 }
    }
  }

  nat_gateway = {
    mode = "single_az"
    az   = "us-east-1a"
  }

  tags = {
    Environment = "development"
    Project     = "web-app"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "subnet_ids" {
  value = module.vpc.subnet_ids_by_group
}

output "subnets_by_role" {
  value = module.vpc.subnet_ids_by_semantic_role
}
