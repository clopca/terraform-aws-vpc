resource "aws_vpclattice_service_network" "enterprise" {
  name      = "enterprise-service-network"
  auth_type = "AWS_IAM"

  tags = {
    Environment = "production"
  }
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
      secondary = {
        shared-services = {
          cidr_block = "100.64.0.0/20"
        }
      }
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
        cidrs_by_az = { "eu-west-1a" = "10.0.32.0/20", "eu-west-1b" = "10.0.48.0/20", "eu-west-1c" = "10.0.64.0/20" }
      }
      ipv6 = { auto_assign = true }
      routing = {
        nat_gateway     = true
        egress_only_igw = true
      }
      tags = { Tier = "application" }
    }

    data = {
      role = "isolated"
      ipv4 = {
        cidrs_by_az = { "eu-west-1a" = "10.0.80.0/22", "eu-west-1b" = "10.0.84.0/22", "eu-west-1c" = "10.0.88.0/22" }
      }
      tags = { Tier = "data", Compliance = "pci-dss" }
    }

    endpoints = {
      role = "isolated"
      ipv4 = {
        cidrs_by_az        = { "eu-west-1a" = "100.64.0.0/26", "eu-west-1b" = "100.64.0.64/26", "eu-west-1c" = "100.64.0.128/26" }
        secondary_cidr_key = "shared-services"
      }
      tags = { Tier = "vpc-endpoints" }
    }
  }

  nat_gateway = {
    mode         = "all_azs"
    subnet_group = "public"
  }

  # Module-owned CloudWatch destination and delivery role keep the example
  # deployable without pre-existing logging infrastructure.
  flow_logs = {
    archive = {
      destination_type = "cloudwatch"
      traffic_type     = "ALL"
      cloudwatch_options = {
        retention_in_days = 365
      }
    }
  }

  vpc_lattice = {
    enabled                    = true
    service_network_identifier = aws_vpclattice_service_network.enterprise.id
    private_dns_enabled        = true
    tags                       = { Tier = "service-network" }
  }

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
