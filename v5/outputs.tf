# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Outputs (Phase 1: Tier 1 real)
#
# Tier 1: Stable Contract — semver-protected, shapes won't change without major bump
# Tier 3: Escape hatch — full resource objects, NO semver guarantee
#
# Tier 2 (deprecated legacy) deferred to Phase 4 (moved blocks + migration).
# ─────────────────────────────────────────────────────────────────────────────

# ═══════════════════════════════════════════════════════════════════════════════
# TIER 1 — STABLE CONTRACT (semver-protected)
# ═══════════════════════════════════════════════════════════════════════════════

output "vpc_id" {
  description = "The ID of the VPC (created or referenced)."
  value       = local.vpc_id
}

output "vpc_cidr_block" {
  description = "The primary IPv4 CIDR block of the VPC."
  value       = local.vpc_cidr
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
  value = {
    for name in keys(var.subnets) : name => [
      for az in local.azs : aws_subnet.main["${name}/${az}"].id
    ]
  }
}

output "subnet_ids_by_role_by_az" {
  description = <<-EOT
    Subnet IDs indexed by subnet group name and AZ.
    Shape: map(subnet_name, map(az, subnet_id))
    Example: { "app" = { "us-east-1a" = "subnet-abc", "us-east-1b" = "subnet-def" } }
  EOT
  value = {
    for name in keys(var.subnets) : name => {
      for az in local.azs : az => aws_subnet.main["${name}/${az}"].id
    }
  }
}

output "subnet_cidrs_by_role_by_az" {
  description = <<-EOT
    Subnet CIDR blocks indexed by subnet group name and AZ.
    Shape: map(subnet_name, map(az, cidr_block))
  EOT
  value = {
    for name in keys(var.subnets) : name => {
      for az in local.azs : az => aws_subnet.main["${name}/${az}"].cidr_block
    }
  }
}

output "subnet_arns_by_role_by_az" {
  description = <<-EOT
    Subnet ARNs indexed by subnet group name and AZ.
    Shape: map(subnet_name, map(az, arn))
  EOT
  value = {
    for name in keys(var.subnets) : name => {
      for az in local.azs : az => aws_subnet.main["${name}/${az}"].arn
    }
  }
}

# Placeholder outputs for Phase 2+ resources (NAT, IGW, TGW, CWAN)
# These will be populated when those phases are implemented.

output "nat_gateway_ids" {
  description = <<-EOT
    NAT Gateway IDs indexed by AZ. Empty map until Phase 2.
    Shape: map(az, nat_gateway_id)
  EOT
  value       = {} # Phase 2
}

output "nat_public_ips" {
  description = <<-EOT
    NAT Gateway public IPs indexed by AZ. Empty map until Phase 2.
    Shape: map(az, public_ip)
  EOT
  value       = {} # Phase 2
}

output "internet_gateway_id" {
  description = "Internet Gateway ID. Null until Phase 2."
  value       = null # Phase 2
}

output "transit_gateway_attachment_id" {
  description = "Transit Gateway VPC Attachment ID. Null until Phase 3."
  value       = null # Phase 3
}

output "core_network_attachment_id" {
  description = "Cloud WAN Core Network Attachment ID. Null until Phase 3."
  value       = null # Phase 3
}

# ═══════════════════════════════════════════════════════════════════════════════
# TIER 3 — ESCAPE HATCH (NO semver guarantee)
# ═══════════════════════════════════════════════════════════════════════════════

output "resources" {
  description = <<-EOT
    UNSTABLE: Raw internal data for advanced composition. Shape may change in any
    minor or patch release. Use Tier 1 outputs for stable integrations.
  EOT
  value = {
    vpc = local.create_vpc ? aws_vpc.main[0] : null
    subnets = {
      for key, subnet in aws_subnet.main : key => {
        id         = subnet.id
        arn        = subnet.arn
        cidr_block = subnet.cidr_block
        az         = subnet.availability_zone
        role       = local.subnet_map[key].role
        name       = local.subnet_map[key].name
      }
    }
    secondary_cidr_associations = {
      for key, assoc in aws_vpc_ipv4_cidr_block_association.secondary : key => {
        id         = assoc.id
        cidr_block = assoc.cidr_block
      }
    }
  }
}
