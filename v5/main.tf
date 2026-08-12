# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Core Resources (main.tf)
#
# Phase 1: VPC (create-or-inject) + addressing + subnets
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

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.vpc.name}-${each.value.name_prefix}-${each.value.az}"
  })

  lifecycle {
    precondition {
      condition     = each.value.cidr_block != null || each.value.ipam_pool_id != null || each.value.ipv6_native
      error_message = "Subnet ${each.key}: must have cidr_block, ipam_pool_id, or be ipv6-native."
    }
  }
}


