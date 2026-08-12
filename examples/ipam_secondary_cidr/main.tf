# ---------- AMAZON VPC IPAM ----------
module "ipam" {
  source  = "aws-ia/ipam/aws"
  version = ">= 2.0.0"

  top_cidr = ["10.0.0.0/8"]

  pool_configurations = {
    (var.aws_region) = {
      description = "${var.aws_region} top level pool"
      cidr        = ["10.0.0.0/16"]
      locale      = var.aws_region
    }
  }
}

# ---------- PRIMARY VPC (using IPAM) ----------
module "vpc" {
  source = "../.."

  name     = "ipam-secondary-example-vpc"
  az_count = 2

  vpc_ipv4_ipam_pool_id   = module.ipam.pools_level_1[var.aws_region].id
  vpc_ipv4_netmask_length = 24

  subnets = {
    public = {
      netmask                   = 28
      nat_gateway_configuration = "single_az"
    }
    private = {
      netmask                 = 28
      connect_to_public_natgw = true
    }
  }
}

# ---------- SECONDARY CIDR (using IPAM for allocation) ----------
# Demonstrates fix for issues #146 and #142: IPAM can now allocate
# the secondary CIDR dynamically instead of requiring a literal CIDR.
module "vpc_secondary_cidr_ipam" {
  source = "../.."

  # Secondary CIDR mode: attach to existing VPC
  vpc_secondary_cidr       = true
  vpc_id                   = module.vpc.vpc_attributes.id
  vpc_secondary_cidr_natgw = module.vpc.natgw_id_per_az

  name     = "ipam-secondary"
  az_count = 2

  # IPAM allocates the secondary CIDR
  vpc_ipv4_ipam_pool_id   = module.ipam.pools_level_1[var.aws_region].id
  vpc_ipv4_netmask_length = 26

  # When using IPAM for secondary CIDRs, use explicit `cidrs` (not `netmask`)
  # because the CIDR is not known until apply time.
  subnets = {
    private = {
      cidrs                   = ["10.0.1.0/28", "10.0.1.16/28"]
      connect_to_public_natgw = true
    }
  }
}
