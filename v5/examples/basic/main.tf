# ─────────────────────────────────────────────────────────────────────────────
# Example 1: Basic — Simple 3-AZ Web Application VPC
# Demonstrates: single_az NAT, EIGW for IPv6, DNS64, route tables,
# and native CloudWatch VPC Flow Logs with a created IAM role
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.29"
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
    ipv6 = { amazon_assigned = true }
  }

  availability_zones = { count = 3 }

  subnets = {
    public = {
      role = "public"
      ipv4 = { netmask = 24 }
      ipv6 = { auto_assign = true }
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
      ipv6 = { auto_assign = true }
      routing = {
        nat_gateway     = true
        egress_only_igw = true
        dns64           = true
      }
    }

    database = {
      role = "isolated"
      ipv4 = { netmask = 24 }
    }
  }

  nat_gateway = {
    mode         = "single_az"
    az           = "us-east-1a"
    subnet_group = "public"
  }

  # Native CloudWatch destination and VPC Flow Logs IAM role are created.
  flow_logs = {
    audit = {
      destination_type = "cloudwatch"
      traffic_type     = "ALL"
      cloudwatch_options = {
        retention_in_days = 30
      }
    }
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

output "subnet_ipv6_cidrs" {
  value = module.vpc.subnet_ipv6_cidrs_by_group_by_az
}

output "subnets_by_role" {
  value = module.vpc.subnet_ids_by_semantic_role
}

output "nat_gateway_ids" {
  value = module.vpc.nat_gateway_ids
}

output "nat_public_ips" {
  value = module.vpc.nat_public_ips
}

output "route_tables" {
  value = module.vpc.route_table_ids_by_group_by_az
}

output "eigw_id" {
  value = module.vpc.egress_only_igw_id
}

output "flow_log_ids" {
  value = module.vpc.flow_log_ids
}
