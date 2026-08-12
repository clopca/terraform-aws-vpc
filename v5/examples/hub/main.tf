# ─────────────────────────────────────────────────────────────────────────────
# Example 3: Hub — Transit Gateway + Cloud WAN with dedicated subnets
# Demonstrates:
#   - Multiple public subnet groups [R1-C1]: "public" + "edge" both public role
#   - Multiple TGW route destinations [R1-C3]: corporate + shared-services
#   - Existing EIPs for NAT [R1-H2]
#   - CIDR pinning [R1-C2]: cidr_index for stable netmask allocation
#   - Private NAT gateway (connectivity_type = "private") for inspection VPC
#   - Real TGW + Cloud WAN attachment resources from dedicated subnet roles
#   - Externally managed Kinesis Data Firehose VPC Flow Logs destination
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
  region = "us-west-2"
}

module "vpc" {
  source = "../.."

  vpc = {
    name       = "network-hub-vpc"
    igw_create = false
    igw_id     = "igw-0123456789abcdef0" # Inject existing IGW [R1-H2]
  }

  addressing = {
    ipv4 = { cidr_block = "10.1.0.0/16" }
    ipv6 = { amazon_assigned = true }
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
      ipv6 = { auto_assign = true, cidr_index = 0 }
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
      ipv6 = { auto_assign = true, cidr_index = 1 }
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
      ipv6 = { auto_assign = true, cidr_index = 2 }
      routing = {
        nat_gateway = true
        # Multiple TGW destinations [R1-C3], including IPv6.
        transit_gateway      = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
        transit_gateway_ipv6 = ["2001:db8:100::/48"]
        # Route workload traffic to Cloud WAN from a non-attachment group.
        core_network      = ["100.64.0.0/10"]
        core_network_ipv6 = ["2001:db8:200::/48"]
      }
      tags = { Purpose = "network-firewall-endpoints" }
    }

    tgw = {
      role = "transit_gateway"
      ipv4 = {
        netmask    = 28
        cidr_index = 64 # 10.1.24.0/28+, outside all explicit ranges
      }
      ipv6 = { auto_assign = true, cidr_index = 3 }
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
        cidr_index = 65 # 10.1.24.96/28+, outside all explicit ranges
      }
      ipv6 = { auto_assign = true, cidr_index = 4 }
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
    mode         = "all_azs"
    subnet_group = "public"
    eip = {
      mode = "existing"
      allocation_ids = {
        "us-west-2a" = "eipalloc-01111111111111111"
        "us-west-2b" = "eipalloc-02222222222222222"
        "us-west-2c" = "eipalloc-03333333333333333"
      }
    }
  }

  # The module creates both attachments. The Firehose stream and its S3/IAM
  # dependencies are externally managed and injected by ARN.
  flow_logs = {
    network = {
      destination_type = "kinesis"
      destination_arn  = "arn:aws:firehose:us-west-2:123456789012:deliverystream/network-hub-vpc-flow-logs"
      traffic_type     = "ALL"
    }
  }

  tags = {
    Environment = "production"
    Role        = "network-hub"
  }
}

# ─── Private NAT example (inspection VPC pattern) ─────────────────────────
# Demonstrates connectivity_type = "private" — NAT without public EIP.

module "inspection_vpc" {
  source = "../.."

  vpc = {
    name = "inspection-vpc"
  }

  addressing = {
    ipv4 = { cidr_block = "100.64.0.0/16" }
  }

  availability_zones = {
    names = ["us-west-2a", "us-west-2b"]
  }

  subnets = {
    firewall = {
      role = "private"
      ipv4 = { netmask = 24 }
      routing = {
        nat_gateway     = true
        transit_gateway = ["10.0.0.0/8"]
      }
    }

    tgw = {
      role = "transit_gateway"
      ipv4 = { netmask = 28 }
      transit_gateway_options = {
        id = "tgw-0123456789abcdef0"
      }
    }

    # Private NAT needs a subnet to live in — but private NAT doesn't require
    # a public subnet, it can be placed in any subnet. We use a dedicated one.
    nat-host = {
      role = "private"
      ipv4 = { netmask = 28 }
    }
  }

  nat_gateway = {
    mode              = "all_azs"
    connectivity_type = "private"
    subnet_group      = "nat-host"
  }

  tags = {
    Environment = "production"
    Role        = "inspection"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "subnet_ids" {
  value = module.vpc.subnet_ids_by_group_by_az
}

output "subnet_ipv6_cidrs" {
  value = module.vpc.subnet_ipv6_cidrs_by_group_by_az
}

output "subnets_by_role" {
  value = module.vpc.subnet_ids_by_semantic_role
}

output "igw_id" {
  value = module.vpc.internet_gateway_id
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

output "route_tables_by_role" {
  value = module.vpc.route_table_ids_by_semantic_role
}

output "inspection_vpc_id" {
  value = module.inspection_vpc.vpc_id
}

output "inspection_nat_ids" {
  value = module.inspection_vpc.nat_gateway_ids
}

output "transit_gateway_attachment_id" {
  value = module.vpc.transit_gateway_attachment_id
}

output "core_network_attachment_id" {
  value = module.vpc.core_network_attachment_id
}

output "flow_log_ids" {
  value = module.vpc.flow_log_ids
}
