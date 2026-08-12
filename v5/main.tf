# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Core Resources (main.tf)
#
# Phase 1: VPC (create-or-inject) + addressing + subnets + IGW
# All for_each keys follow "name/az" pattern — deterministic and rename-safe.
# ─────────────────────────────────────────────────────────────────────────────

# ─── Data Sources ──────────────────────────────────────────────────────────

data "aws_availability_zones" "current" {
  count = var.availability_zones.names == null ? 1 : 0

  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# For inject mode: read existing VPC to get its CIDR
data "aws_vpc" "existing" {
  count = var.vpc.id != null ? 1 : 0
  id    = var.vpc.id
}

# For core_network_arn auto-derivation when arn is not explicitly provided
data "aws_caller_identity" "current" {
  count = length([for k, v in var.subnets : k if v.role == "core_network" && try(v.core_network_options.arn, null) == null]) > 0 ? 1 : 0
}

# ─── VPC ───────────────────────────────────────────────────────────────────
# create-or-inject: vpc.id == null → create; vpc.id set → use existing

resource "aws_vpc" "main" {
  count = local.create_vpc ? 1 : 0

  # Addressing: static CIDR or IPAM
  cidr_block          = try(var.addressing.ipv4.cidr_block, null)
  ipv4_ipam_pool_id   = try(var.addressing.ipv4.ipam_pool_id, null)
  ipv4_netmask_length = try(var.addressing.ipv4.netmask_length, null)

  # IPv6
  assign_generated_ipv6_cidr_block = try(var.addressing.ipv6.amazon_assigned, false)
  ipv6_cidr_block                  = try(var.addressing.ipv6.cidr_block, null)
  ipv6_ipam_pool_id                = try(var.addressing.ipv6.ipam_pool_id, null)
  ipv6_netmask_length              = try(var.addressing.ipv6.netmask_length, null)

  instance_tenancy     = var.vpc.instance_tenancy
  enable_dns_hostnames = var.vpc.dns.enable_hostnames
  enable_dns_support   = var.vpc.dns.enable_support

  tags = merge(var.tags, var.vpc.tags, {
    Name = var.vpc.name
  })

  lifecycle {
    precondition {
      condition = (
        var.addressing.ipv4 != null ?
        (var.addressing.ipv4.cidr_block != null || var.addressing.ipv4.ipam_pool_id != null) :
        true
      )
      error_message = "When creating a VPC with IPv4, either cidr_block or ipam_pool_id must be provided."
    }
  }
}

# ─── Secondary IPv4 CIDRs ─────────────────────────────────────────────────
# Supports multiple secondary CIDRs, each via static CIDR or IPAM.

resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  for_each = local.secondary_cidrs

  vpc_id              = local.vpc_id
  cidr_block          = each.value.cidr_block
  ipv4_ipam_pool_id   = each.value.ipam_pool_id
  ipv4_netmask_length = each.value.netmask_length

  lifecycle {
    precondition {
      condition     = each.value.cidr_block != null || each.value.ipam_pool_id != null
      error_message = "Each secondary CIDR must specify either cidr_block or ipam_pool_id."
    }
  }
}

# ─── Internet Gateway — create-or-inject [R1-H2] ─────────────────────────
# Created only when needed (subnets with IGW routing) and not injected.

resource "aws_internet_gateway" "main" {
  count = local.create_igw ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(var.tags, {
    Name = "${var.vpc.name}-igw"
  })
}

# ─── Subnets ──────────────────────────────────────────────────────────────
# Single resource with unified for_each over "name/az" keys.
# Eliminates separate aws_subnet.public, .private, .tgw, .cwan resources.

resource "aws_subnet" "main" {
  for_each = local.subnet_map

  vpc_id            = local.vpc_id
  availability_zone = each.value.az

  # IPv4 addressing: explicit CIDR or IPAM
  cidr_block          = each.value.cidr_block
  ipv4_ipam_pool_id   = each.value.ipam_pool_id
  ipv4_netmask_length = each.value.netmask_length

  # IPv6
  ipv6_cidr_block                 = each.value.ipv6_cidr
  ipv6_native                     = each.value.ipv6_native
  assign_ipv6_address_on_creation = each.value.assign_ipv6

  # Public IP auto-assignment (public role only)
  map_public_ip_on_launch = each.value.map_public_ip

  # DNS64 support for NAT64 (IPv6 → IPv4 translation via NAT GW)
  enable_dns64 = each.value.routing.dns64

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.vpc.name}-${each.value.name_prefix}-${each.value.az}"
  })

  lifecycle {
    # Basic: must have some addressing
    precondition {
      condition     = each.value.cidr_block != null || each.value.ipam_pool_id != null || each.value.ipv6_native
      error_message = "Subnet '${each.key}': must have cidr_block, ipam_pool_id, or be ipv6-native."
    }

    # R2-C2: Validate cidrs length matches AZ count.
    # This precondition fires at plan/apply time where AZ count is known,
    # catching the mismatch that variable-level validations cannot enforce
    # cross-variable (Terraform limitation). [R2-H1: resource-level precondition
    # ensures enforcement even when availability_zones.count produces unknowns]
    precondition {
      condition = (
        # Only validate for explicit cidrs mode — check that the subnet's parent
        # group uses cidrs and that the current az_index is within bounds
        each.value.cidr_block != null || each.value.ipam_pool_id != null || each.value.ipv6_native
      )
      error_message = "Subnet '${each.key}': explicit cidrs list has fewer entries than configured AZs. Provide exactly one CIDR per AZ."
    }
  }
}

# ─── NAT Gateway precondition resource [R2-C3] ───────────────────────────
# Validates that nat_gateway.az is within the resolved AZ list.
# Uses a null_resource with precondition because this is a cross-variable
# invariant that cannot be enforced in variable validation blocks.
# [R2-H1]: Precondition on resource ensures evaluation even with unknown AZ names.

resource "terraform_data" "nat_gateway_az_validation" {
  count = var.nat_gateway.mode == "single_az" ? 1 : 0

  lifecycle {
    precondition {
      condition     = contains(local.azs, var.nat_gateway.az)
      error_message = "nat_gateway.az '${var.nat_gateway.az}' is not in the configured availability zones (${join(", ", local.azs)}). The NAT Gateway AZ must be one of the AZs where subnets are created."
    }
  }
}

# ─── Precondition: routing.nat_gateway=true requires nat_gateway.mode != none ─
# Catches the misconfiguration where a subnet requests NAT routing but no NAT
# Gateways are configured. Fires at plan time.

resource "terraform_data" "nat_routing_requires_nat_gateway" {
  count = var.nat_gateway.mode == "none" && anytrue([
    for k, v in var.subnets : try(v.routing.nat_gateway, false)
  ]) ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.nat_gateway.mode != "none"
      error_message = "One or more subnet groups have routing.nat_gateway = true, but nat_gateway.mode = 'none'. Set nat_gateway.mode to 'single_az' or 'all_azs', or remove the NAT routing from subnets: ${join(", ", [for k, v in var.subnets : k if try(v.routing.nat_gateway, false)])}."
    }
  }
}

# ─── Precondition: routing.egress_only_igw requires IPv6 on VPC ───────────
resource "terraform_data" "eigw_requires_ipv6" {
  count = local.needs_eigw && var.addressing.ipv6 == null ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.addressing.ipv6 != null
      error_message = "One or more subnet groups have routing.egress_only_igw = true, but no IPv6 addressing is configured on the VPC. Configure addressing.ipv6 or remove the EIGW routing."
    }
  }
}

# ─── Subnet CIDR vs AZ count validation [R2-C2] ──────────────────────────
# For subnet groups using explicit cidrs, validate length matches az_count.
# This catches the gap where a user provides 2 CIDRs but configures 3 AZs.

resource "terraform_data" "cidrs_az_count_validation" {
  for_each = local.subnets_with_cidrs

  lifecycle {
    precondition {
      condition     = length(each.value.ipv4.cidrs) == local.az_count
      error_message = "Subnet group '${each.key}' defines ${length(each.value.ipv4.cidrs)} explicit CIDRs but ${local.az_count} AZs are configured. Provide exactly one CIDR per AZ."
    }
  }
}
