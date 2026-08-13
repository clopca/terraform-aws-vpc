# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Outputs Contract (Prototype)
#
# Tier 1: Stable Contract — semver-protected, shapes won't change without major bump
# Tier 2: Deprecated legacy — present in v5, removed in v6
# Tier 3: Escape hatch — full resource objects, NO semver guarantee
#
# This prototype uses locals to demonstrate output shapes without creating real
# resources. In the real module, these derive from aws_subnet.main, etc.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # Derive AZ list from input for output shape demonstration
  azs = coalesce(
    var.availability_zones.names,
    try(["us-east-1a", "us-east-1b", "us-east-1c"], [])
  )

  # Derive subnet groups by role
  public_subnets   = { for k, v in var.subnets : k => v if v.role == "public" }
  private_subnets  = { for k, v in var.subnets : k => v if v.role == "private" }
  isolated_subnets = { for k, v in var.subnets : k => v if v.role == "isolated" }
  tgw_subnets      = { for k, v in var.subnets : k => v if v.role == "transit_gateway" }
  cwan_subnets     = { for k, v in var.subnets : k => v if v.role == "core_network" }

  # Build the unified key space: "subnet_name/az" for all subnets
  all_subnet_keys = flatten([
    for name, cfg in var.subnets : [
      for az in local.azs : "${name}/${az}"
    ]
  ])

  # Dummy subnet IDs grouped by role (in real module: derived from aws_subnet.main)
  subnet_ids_by_role = merge(
    { for k, v in local.public_subnets : k => [for az in local.azs : "subnet-${k}-${az}-placeholder"] },
    { for k, v in local.private_subnets : k => [for az in local.azs : "subnet-${k}-${az}-placeholder"] },
    { for k, v in local.isolated_subnets : k => [for az in local.azs : "subnet-${k}-${az}-placeholder"] },
    { for k, v in local.tgw_subnets : k => [for az in local.azs : "subnet-${k}-${az}-placeholder"] },
    { for k, v in local.cwan_subnets : k => [for az in local.azs : "subnet-${k}-${az}-placeholder"] },
  )

  # Dummy subnet IDs by role by AZ
  subnet_ids_by_role_by_az = {
    for name, cfg in var.subnets : name => {
      for az in local.azs : az => "subnet-${name}-${az}-placeholder"
    }
  }

  # Dummy route table IDs
  route_table_ids = {
    for name, cfg in var.subnets : name => {
      for az in local.azs : az => "rtb-${name}-${az}-placeholder"
    }
  }

  # NAT gateway IDs (only if mode != none)
  nat_azs = (
    var.nat_gateway.mode == "all_azs" ? local.azs :
    var.nat_gateway.mode == "single_az" ? [var.nat_gateway.az] :
    []
  )

  nat_gateway_ids = { for az in local.nat_azs : az => "nat-${az}-placeholder" }
  nat_public_ips  = { for az in local.nat_azs : az => "203.0.113.${index(local.nat_azs, az) + 1}" }
}

# ═══════════════════════════════════════════════════════════════════════════════
# TIER 1 — STABLE CONTRACT (semver-protected)
# These outputs will NOT change shape/keys without a major version bump.
# ═══════════════════════════════════════════════════════════════════════════════

output "vpc_id" {
  description = "The ID of the VPC (created or referenced)."
  value       = var.vpc.id != null ? var.vpc.id : "vpc-placeholder-created"
}

output "vpc_cidr_block" {
  description = "The primary IPv4 CIDR block of the VPC."
  value       = try(var.addressing.ipv4.cidr_block, "10.0.0.0/16")
}

output "azs" {
  description = "List of Availability Zones where subnets were created."
  value       = local.azs
}

output "subnet_ids_by_role" {
  description = <<-EOT
    Subnet IDs grouped by subnet group name (map key).
    Shape: map(subnet_name, list(subnet_id))
    Example: { "public" = ["subnet-abc", "subnet-def"], "app" = [...] }
  EOT
  value       = local.subnet_ids_by_role
}

output "subnet_ids_by_role_by_az" {
  description = <<-EOT
    Subnet IDs indexed by subnet group name and AZ.
    Shape: map(subnet_name, map(az, subnet_id))
    Example: { "app" = { "us-east-1a" = "subnet-abc", "us-east-1b" = "subnet-def" } }
  EOT
  value       = local.subnet_ids_by_role_by_az
}

output "route_table_ids" {
  description = <<-EOT
    Route table IDs indexed by subnet group name and AZ.
    Shape: map(subnet_name, map(az, route_table_id))
  EOT
  value       = local.route_table_ids
}

output "nat_gateway_ids" {
  description = <<-EOT
    NAT Gateway IDs indexed by AZ. Empty map if nat_gateway.mode = "none".
    Shape: map(az, nat_gateway_id)
  EOT
  value       = local.nat_gateway_ids
}

output "nat_public_ips" {
  description = <<-EOT
    NAT Gateway public IPs indexed by AZ. Useful for allowlisting.
    Shape: map(az, public_ip)
  EOT
  value       = local.nat_public_ips
}

output "internet_gateway_id" {
  description = "Internet Gateway ID. Null if no public subnet exists."
  value       = length(local.public_subnets) > 0 ? "igw-placeholder" : null
}

output "transit_gateway_attachment_id" {
  description = "Transit Gateway VPC Attachment ID. Null if no TGW subnet exists."
  value       = length(local.tgw_subnets) > 0 ? "tgw-attach-placeholder" : null
}

output "core_network_attachment_id" {
  description = "Cloud WAN Core Network Attachment ID. Null if no core_network subnet exists."
  value       = length(local.cwan_subnets) > 0 ? "cwan-attach-placeholder" : null
}

# ═══════════════════════════════════════════════════════════════════════════════
# TIER 2 — DEPRECATED LEGACY (v4 compatibility, removed in v6)
# ═══════════════════════════════════════════════════════════════════════════════

output "private_subnet_attributes_by_az" {
  description = "DEPRECATED: Use subnet_ids_by_role_by_az instead. Will be removed in v6.0."
  value = {
    for name, cfg in var.subnets : "${name}" => {
      for az in local.azs : "${name}/${az}" => {
        id  = "subnet-${name}-${az}-placeholder"
        arn = "arn:aws:ec2:us-east-1:123456789012:subnet/subnet-${name}-${az}-placeholder"
      }
    } if contains(["private", "isolated"], cfg.role)
  }
}

output "public_subnet_attributes_by_az" {
  description = "DEPRECATED: Use subnet_ids_by_role_by_az[\"public\"] instead. Will be removed in v6.0."
  value = {
    for az in local.azs : az => {
      id  = "subnet-public-${az}-placeholder"
      arn = "arn:aws:ec2:us-east-1:123456789012:subnet/subnet-public-${az}-placeholder"
    } if length(local.public_subnets) > 0
  }
}

output "nat_gateway_attributes_by_az" {
  description = "DEPRECATED: Use nat_gateway_ids and nat_public_ips instead. Will be removed in v6.0."
  value = {
    for az in local.nat_azs : az => {
      id        = "nat-${az}-placeholder"
      public_ip = "203.0.113.${index(local.nat_azs, az) + 1}"
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# TIER 3 — ESCAPE HATCH (NO semver guarantee, may change in any release)
# ═══════════════════════════════════════════════════════════════════════════════

output "resources" {
  description = <<-EOT
    UNSTABLE: Raw internal data for advanced composition. Shape may change in any
    minor or patch release. Use Tier 1 outputs for stable integrations.
  EOT
  value = {
    all_subnet_keys = local.all_subnet_keys
    subnet_config   = var.subnets
    nat_config      = var.nat_gateway
  }
}
