# ─────────────────────────────────────────────────────────────────────────────
# Example 3: Hub — Transit Gateway + Cloud WAN with dedicated subnets
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
  region = "us-west-2"
}

module "vpc" {
  source = "../.."

  vpc = {
    name = "network-hub-vpc"
  }

  addressing = {
    ipv4 = { cidr_block = "10.1.0.0/16" }
  }

  availability_zones = {
    names = ["us-west-2a", "us-west-2b", "us-west-2c"]
  }

  subnets = {
    public = {
      role = "public"
      ipv4 = {
        cidrs = ["10.1.0.0/24", "10.1.1.0/24", "10.1.2.0/24"]
      }
      routing = {
        internet_gateway = true
      }
      public_options = {
        map_public_ip = false
      }
    }

    firewall = {
      role = "private"
      ipv4 = {
        cidrs = ["10.1.16.0/28", "10.1.16.16/28", "10.1.16.32/28"]
      }
      routing = {
        nat_gateway = true
      }
      tags = { Purpose = "network-firewall-endpoints" }
    }

    tgw = {
      role = "transit_gateway"
      ipv4 = { netmask = 28 }
      routing = {
        nat_gateway = true
      }
      transit_gateway_options = {
        id                              = "tgw-0123456789abcdef0"
        default_route_table_association = false
        default_route_table_propagation = false
        appliance_mode_support          = true
        dns_support                     = true
      }
    }

    cwan = {
      role = "core_network"
      ipv4 = { netmask = 28 }
      core_network_options = {
        id                 = "cnet-0123456789abcdef0"
        arn                = "arn:aws:networkmanager::123456789012:core-network/cnet-0123456789abcdef0"
        appliance_mode     = false
        require_acceptance = true
        accept_attachment  = true
      }
    }
  }

  nat_gateway = {
    mode = "all_azs"
    eip = {
      mode = "existing"
      allocation_ids = {
        "us-west-2a" = "eipalloc-aaa111"
        "us-west-2b" = "eipalloc-bbb222"
        "us-west-2c" = "eipalloc-ccc333"
      }
    }
  }

  tags = {
    Environment = "production"
    Role        = "network-hub"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "subnet_ids" {
  value = module.vpc.subnet_ids_by_role_by_az
}

output "tgw_attachment_id" {
  value = module.vpc.transit_gateway_attachment_id
}

output "cwan_attachment_id" {
  value = module.vpc.core_network_attachment_id
}
