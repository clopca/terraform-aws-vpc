module "vpc" {
  source = "../.."

  vpc = {
    name = "secure-isolated-vpc"
    dns = {
      enable_hostnames = true
      enable_support   = true
    }
  }

  addressing = {
    ipv4 = { cidr_block = var.vpc_cidr }
  }

  availability_zones = {
    names = var.availability_zones
  }

  subnets = {
    enclave = {
      role = "isolated"
      ipv4 = {
        cidrs = [
          for index, az in var.availability_zones :
          cidrsubnet(var.vpc_cidr, 8, index)
        ]
      }
      tags = {
        DataClassification = "restricted"
      }
    }

    control = {
      role = "isolated"
      ipv4 = {
        cidrs = [
          for index, az in var.availability_zones :
          cidrsubnet(var.vpc_cidr, 8, index + 16)
        ]
      }
      tags = {
        Purpose = "offline-control-plane"
      }
    }
  }

  # Regional/account singleton: manage from exactly one module instance.
  vpc_block_public_access = {
    enabled                     = true
    internet_gateway_block_mode = "block-bidirectional"
  }

  dhcp_options = {
    enabled             = true
    domain_name         = "secure.internal"
    domain_name_servers = ["AmazonProvidedDNS"]
    ntp_servers         = ["169.254.169.123"]
    tags = {
      SecurityBoundary = "air-gapped"
    }
  }

  tags = {
    Environment      = "restricted"
    SecurityBoundary = "air-gapped"
  }
}
