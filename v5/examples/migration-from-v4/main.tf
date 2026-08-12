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

# This skeleton preserves the v4 reserved group names so every deprecated
# Tier 2 output keeps its exact v4 key shape during the transition.
module "vpc" {
  source = "../.."

  vpc = {
    name             = "migration-example"
    igw_name_format  = "{vpc}-igw" # v4: "${var.name}-igw"
    eigw_name_format = "{vpc}"     # v4: var.name
  }

  addressing = {
    ipv4 = { cidr_block = "10.42.0.0/16" }
    ipv6 = { amazon_assigned = true }
  }

  availability_zones = {
    names = ["us-east-1a", "us-east-1b"]
  }

  subnets = {
    public = {
      role        = "public"
      name_format = "{group}-{az}" # v4: "${name_prefix || key}-${az}"
      ipv4        = { cidrs = ["10.42.0.0/24", "10.42.1.0/24"] }
      # Replace with the prefixes already recorded in v4 state.
      ipv6 = { cidrs = ["2600:1f18:4200:1::/64", "2600:1f18:4200:2::/64"], auto_assign = true }
      routing = {
        internet_gateway     = true
        transit_gateway      = ["10.0.0.0/8"]
        transit_gateway_ipv6 = ["2001:db8:100::/48"]
        core_network         = ["100.64.0.0/10"]
        core_network_ipv6    = ["2001:db8:300::/48"]
      }
      public_options = { map_public_ip = true }
    }

    app = {
      role        = "private"
      name_format = "{group}-{az}"
      ipv4        = { cidrs = ["10.42.16.0/20", "10.42.32.0/20"] }
      ipv6        = { cidrs = ["2600:1f18:4200:10::/64", "2600:1f18:4200:11::/64"], auto_assign = true }
      routing = {
        nat_gateway          = true
        egress_only_igw      = true
        transit_gateway      = ["172.16.0.0/12"]
        transit_gateway_ipv6 = ["2001:db8:200::/48"]
        core_network         = ["192.168.0.0/16"]
        core_network_ipv6    = ["2001:db8:400::/48"]
      }
    }

    transit_gateway = {
      role        = "transit_gateway"
      name_format = "{group}-{az}"
      ipv4        = { cidrs = ["10.42.240.0/28", "10.42.240.16/28"] }
      ipv6        = { cidrs = ["2600:1f18:4200:f0::/64", "2600:1f18:4200:f1::/64"] }
      routing     = { nat_gateway = true }
      transit_gateway_options = {
        id = "tgw-0123456789abcdef0"
      }
    }

    core_network = {
      role        = "core_network"
      name_format = "{group}-{az}"
      ipv4        = { cidrs = ["10.42.241.0/28", "10.42.241.16/28"] }
      ipv6        = { cidrs = ["2600:1f18:4200:f2::/64", "2600:1f18:4200:f3::/64"] }
      routing     = { nat_gateway = true }
      core_network_options = {
        id  = "cnet-0123456789abcdef0"
        arn = "arn:aws:networkmanager::123456789012:core-network/cnet-0123456789abcdef0"
      }
    }
  }

  nat_gateway = {
    mode         = "all_azs"
    subnet_group = "public"
    name_format  = "nat-{group}-{az}" # v4 EIP and NAT Name formula
  }

  flow_logs = {
    default = {
      destination_type = "cloudwatch"
      traffic_type     = "ALL"

      # Replace both values with the exact v4 state values before planning.
      # The log group is imported at the v5 address; the role uses a moved block.
      role_name_prefix = "migration-example-cw-access-role-"
      cloudwatch_options = {
        name = "migration-example-vpc-flow-logs-20260812123456789000000001"
      }
    }
  }

  vpc_lattice = {
    enabled                    = true
    service_network_identifier = "sn-0123456789abcdef0"
  }

  tags = {
    ManagedBy = "terraform"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "subnet_ids_by_group_by_az" {
  value = module.vpc.subnet_ids_by_group_by_az
}

# Keep old downstreams operational while migrating them to Tier 1.
output "v4_private_subnet_attributes_by_az" {
  value = module.vpc.private_subnet_attributes_by_az
}

output "v4_name_compatibility" {
  description = "Representative Name tags that must remain identical during v4 migration."
  value = {
    public_subnet    = module.vpc.resources.subnets["public/us-east-1a"].tags.Name
    app_route_table  = module.vpc.resources.route_tables["app/us-east-1a"].tags.Name
    nat_eip          = module.vpc.resources.eips["nat/us-east-1a"].tags.Name
    nat_gateway      = module.vpc.resources.nat_gateways["nat/us-east-1a"].tags.Name
    internet_gateway = module.vpc.resources.internet_gateway[0].tags.Name
    egress_only_igw  = module.vpc.resources.egress_only_internet_gateway[0].tags.Name
  }
}
