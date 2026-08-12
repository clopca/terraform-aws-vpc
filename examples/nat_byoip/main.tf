# ---------- BYOIP NAT Gateway Example ----------
# Demonstrates three modes of EIP sourcing for NAT Gateways:
# 1. BYOIP pool allocation (mode = "byoip_pool")
# 2. Pre-existing EIP injection (mode = "existing")
# Default mode ("create") is the existing behaviour — see examples/basic.

# --- Mode: byoip_pool ---
# Allocates EIPs from a customer-owned public IPv4 pool.
module "vpc_byoip_pool" {
  source = "../.."

  name       = "byoip-pool-example"
  cidr_block = "10.0.0.0/16"
  az_count   = 2

  subnets = {
    public = {
      netmask                   = 24
      nat_gateway_configuration = "all_azs"
    }
    private = {
      netmask                 = 24
      connect_to_public_natgw = true
    }
  }

  nat_gateway_eip_configuration = {
    mode             = "byoip_pool"
    public_ipv4_pool = var.public_ipv4_pool
  }
}

# --- Mode: existing ---
# Uses pre-allocated EIP allocation IDs. Useful when EIPs are managed
# outside of Terraform or shared across stacks.
module "vpc_existing_eips" {
  source = "../.."

  name       = "existing-eip-example"
  cidr_block = "10.1.0.0/16"
  az_count   = 2

  subnets = {
    public = {
      netmask                   = 24
      nat_gateway_configuration = "all_azs"
    }
    private = {
      netmask                 = 24
      connect_to_public_natgw = true
    }
  }

  nat_gateway_eip_configuration = {
    mode           = "existing"
    allocation_ids = var.existing_eip_allocation_ids
  }
}
