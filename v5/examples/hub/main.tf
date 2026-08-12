# ─────────────────────────────────────────────────────────────────────────────
# Example 3: Hub — Transit Gateway + Cloud WAN with dedicated subnets
# Demonstrates:
#   - Multiple public subnet groups [R1-C1]: "public" + "edge" both public role
#   - Multiple TGW route destinations [R1-C3]: corporate + shared-services
#   - IGW injection [R1-H2]: bring your own IGW
#   - CIDR pinning [R1-C2]: cidr_index for stable netmask allocation
#   - Existing NAT GW injection [R1-H2]
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
  region = "us-west-2"
}

module "vpc" {
  source = "../.."

  vpc = {
    name = "network-hub-vpc"
    # igw_id = "igw-existing123"  # Uncomment to inject existing IGW [R1-H2]
  }

  addressing = {
    ipv4 = { cidr_block = "10.1.0.0/16" }
  }

  availability_zones = {
    names = ["us-west-2a", "us-west-2b", "us-west-2c"]
  }

  subnets = {
    # Multiple public groups allowed [R1-C1]
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

    # Second public group for edge/GWLB [R1-C1]
    edge = {
      role = "public"
      ipv4 = {
        cidrs = ["10.1.3.0/24", "10.1.4.0/24", "10.1.5.0/24"]
      }
      routing = {
        internet_gateway = true
      }
      public_options = {
        map_public_ip = false
      }
      tags = { Purpose = "gwlb-endpoints" }
    }

    firewall = {
      role = "private"
      ipv4 = {
        cidrs = ["10.1.16.0/28", "10.1.16.16/28", "10.1.16.32/28"]
      }
      routing = {
        nat_gateway = true
        # Multiple TGW destinations [R1-C3]:
        # Route corporate and shared-services CIDRs to TGW
        transit_gateway = ["10.0.0.0/8", "172.16.0.0/12"]
      }
      tags = { Purpose = "network-firewall-endpoints" }
    }

    tgw = {
      role = "transit_gateway"
      ipv4 = {
        netmask    = 28
        cidr_index = 0 # Pinned: immune to other group additions [R1-C2]
      }
      routing = {
        nat_gateway = true
      }
      transit_gateway_options = {
        id                              = "tgw-0123456789abcdef0"
        default_route_table_association = false
        default_route_table_propagation = false
        appliance_mode_support          = true
        dns_support                     = true
        security_group_referencing      = true
      }
    }

    cwan = {
      role = "core_network"
      ipv4 = {
        netmask    = 28
        cidr_index = 1 # Pinned: immune to other group additions [R1-C2]
      }
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
    # existing_ids = {  # Uncomment to inject existing NAT GWs [R1-H2]
    #   "us-west-2a" = "nat-aaa111"
    #   "us-west-2b" = "nat-bbb222"
    #   "us-west-2c" = "nat-ccc333"
    # }
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
  value = module.vpc.subnet_ids_by_group_by_az
}

output "subnets_by_role" {
  value = module.vpc.subnet_ids_by_semantic_role
}

output "igw_id" {
  value = module.vpc.internet_gateway_id
}

output "tgw_attachment_id" {
  value = module.vpc.transit_gateway_attachment_id
}

output "cwan_attachment_id" {
  value = module.vpc.core_network_attachment_id
}
