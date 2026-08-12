# ─────────────────────────────────────────────────────────────────────────────
# Example 2: Enterprise — IPAM + Explicit CIDRs + Multiple Tiers
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

module "vpc" {
  source = "../.."

  vpc = {
    name             = "enterprise-vpc"
    instance_tenancy = "default"
    dns = {
      enable_hostnames = true
      enable_support   = true
    }
    tags = { CostCenter = "platform-team" }
  }

  addressing = {
    ipv4 = {
      cidr_block = "10.0.0.0/16"
      secondary = [{
        cidr_block = "100.64.0.0/20"
      }]
    }
    ipv6 = {
      amazon_assigned = true
    }
  }

  availability_zones = {
    names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  }

  subnets = {
    public = {
      role = "public"
      ipv4 = { netmask = 24 }
      ipv6 = { auto_assign = true }
      routing = {
        internet_gateway = true
      }
      public_options = {
        map_public_ip = false
      }
    }

    application = {
      role = "private"
      ipv4 = {
        cidrs = ["10.0.32.0/20", "10.0.48.0/20", "10.0.64.0/20"]
      }
      ipv6 = { auto_assign = true }
      routing = {
        nat_gateway = true
      }
      tags = { Tier = "application" }
    }

    data = {
      role = "isolated"
      ipv4 = {
        cidrs = ["10.0.80.0/22", "10.0.84.0/22", "10.0.88.0/22"]
      }
      tags = { Tier = "data", Compliance = "pci-dss" }
    }

    endpoints = {
      role = "isolated"
      ipv4 = { netmask = 26 }
      tags = { Tier = "vpc-endpoints" }
    }
  }

  nat_gateway = {
    mode = "all_azs"
    eip = {
      mode = "create"
    }
  }

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "subnet_ids" {
  value = module.vpc.subnet_ids_by_role_by_az
}

output "subnet_cidrs" {
  value = module.vpc.subnet_cidrs_by_role_by_az
}
