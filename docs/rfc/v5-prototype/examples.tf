# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Example Configurations (Fixture)
#
# Three scenarios demonstrating the typed contract UX:
#   1. Basic: simple 3-AZ VPC with public + private subnets
#   2. Enterprise: BYOIP EIPs, IPAM, multiple private tiers, flow logs
#   3. Hub: Transit Gateway attachment with dedicated subnets + routing
#
# These are defined as locals (not module calls) since this prototype
# validates the schema — not the implementation.
# ─────────────────────────────────────────────────────────────────────────────

# ═══════════════════════════════════════════════════════════════════════════════
# EXAMPLE 1: Basic — Simple 3-AZ Web Application VPC
# ═══════════════════════════════════════════════════════════════════════════════

locals {
  example_basic = {
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
        # No routing — truly isolated
      }
    }

    nat_gateway = {
      mode = "single_az"
      az   = "us-east-1a" # explicit — no positional fragility
    }

    tags = {
      Environment = "development"
      Project     = "web-app"
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# EXAMPLE 2: Enterprise — BYOIP + IPAM + Multiple Tiers + Flow Logs
# ═══════════════════════════════════════════════════════════════════════════════

locals {
  example_enterprise = {
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
        ipam_pool_id   = "ipam-pool-0123456789abcdef0"
        netmask_length = 16
        secondary = [{
          ipam_pool_id   = "ipam-pool-0fedcba9876543210"
          netmask_length = 20
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
          map_public_ip = false # Enterprise: no auto-assign public IPs
        }
      }

      application = {
        role = "private"
        ipv4 = {
          cidrs = ["10.0.32.0/20", "10.0.48.0/20", "10.0.64.0/20"]
        }
        ipv6 = { auto_assign = true }
        routing = {
          nat_gateway     = true
          egress_only_igw = true
          transit_gateway = "10.100.0.0/8" # Corporate backbone
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
        mode             = "byoip_pool"
        public_ipv4_pool = "ipv4pool-ec2-0123456789abcdef0"
      }
    }

    egress_only_internet_gateway = true

    flow_logs = {
      enabled         = true
      destination     = "s3"
      traffic_type    = "ALL"
      log_destination = "arn:aws:s3:::my-flow-logs-bucket"
      s3_options = {
        file_format                = "parquet"
        hive_compatible_partitions = true
        per_hour_partition         = true
      }
    }

    tags = {
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# EXAMPLE 3: Hub — Transit Gateway with Dedicated Subnets + Cloud WAN
# ═══════════════════════════════════════════════════════════════════════════════

locals {
  example_hub = {
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
          transit_gateway  = "10.0.0.0/8" # Return route to spokes
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
          nat_gateway = true # TGW subnets route to NAT for internet-bound spoke traffic
        }
        transit_gateway_options = {
          id                              = "tgw-0123456789abcdef0"
          default_route_table_association = false # custom routing
          default_route_table_propagation = false
          appliance_mode_support          = true # for inspection VPC
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

    flow_logs = {
      enabled      = true
      destination  = "cloudwatch"
      traffic_type = "ALL"
      iam_role_arn = "arn:aws:iam::123456789012:role/vpc-flow-logs-role"
    }

    vpc_lattice = {
      service_network_identifier = "sn-0123456789abcdef0"
      security_group_ids         = ["sg-lattice001"]
    }

    tags = {
      Environment = "production"
      Role        = "network-hub"
    }
  }
}
