# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Outputs (Phase 1: Tier 1 real)
#
# Tier 1: Stable Contract — semver-protected, shapes won't change without major bump
# Tier 3: Escape hatch — full resource objects, NO semver guarantee
#
# Outputs are organized by SEMANTIC ROLE as well as by group name [R1-H3]:
# - subnet_ids_by_group:         keyed by user's map key (group name)
# - subnet_ids_by_semantic_role: keyed by role (public, private, isolated, etc.)
# Both are Tier 1. Downstream modules should prefer by_semantic_role for loose coupling.
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

# ─── By Group Name (user's map key) ──────────────────────────────────────

output "subnet_ids_by_group" {
  description = <<-EOT
    Subnet IDs grouped by subnet group name (the user's map key).
    Shape: map(group_name, list(subnet_id))
    Example: { "public" = ["subnet-abc", "subnet-def"], "app" = [...] }
  EOT
  value = {
    for name in keys(var.subnets) : name => [
      for az in local.azs : aws_subnet.main["${name}/${az}"].id
    ]
  }
}

output "subnet_ids_by_group_by_az" {
  description = <<-EOT
    Subnet IDs indexed by subnet group name and AZ.
    Shape: map(group_name, map(az, subnet_id))
    Example: { "app" = { "us-east-1a" = "subnet-abc", "us-east-1b" = "subnet-def" } }
  EOT
  value = {
    for name in keys(var.subnets) : name => {
      for az in local.azs : az => aws_subnet.main["${name}/${az}"].id
    }
  }
}

output "subnet_cidrs_by_group_by_az" {
  description = <<-EOT
    Subnet CIDR blocks indexed by subnet group name and AZ.
    Shape: map(group_name, map(az, cidr_block))
  EOT
  value = {
    for name in keys(var.subnets) : name => {
      for az in local.azs : az => aws_subnet.main["${name}/${az}"].cidr_block
    }
  }
}

output "subnet_arns_by_group_by_az" {
  description = <<-EOT
    Subnet ARNs indexed by subnet group name and AZ.
    Shape: map(group_name, map(az, arn))
  EOT
  value = {
    for name in keys(var.subnets) : name => {
      for az in local.azs : az => aws_subnet.main["${name}/${az}"].arn
    }
  }
}

# ─── By Semantic Role [R1-H3] ────────────────────────────────────────────
# Downstream modules (hubandspoke, cloudwan) should consume these outputs
# to avoid coupling to the caller's specific group names.

output "subnet_ids_by_semantic_role" {
  description = <<-EOT
    Subnet IDs grouped by semantic role (public, private, isolated, transit_gateway, core_network).
    Aggregates ALL subnet groups that share a role into a single flat list.
    Shape: map(role, list(subnet_id))
    Example: { "private" = ["subnet-app-a", "subnet-app-b", "subnet-data-a", ...] }
  EOT
  value = {
    for role in ["public", "private", "isolated", "transit_gateway", "core_network"] :
    role => flatten([
      for name, cfg in var.subnets : [
        for az in local.azs : aws_subnet.main["${name}/${az}"].id
      ] if cfg.role == role
    ])
  }
}

output "subnet_ids_by_semantic_role_by_az" {
  description = <<-EOT
    Subnet IDs grouped by semantic role and AZ. For roles with multiple groups,
    subnet IDs from all groups in that role are combined per-AZ.
    Shape: map(role, map(az, list(subnet_id)))
  EOT
  value = {
    for role in ["public", "private", "isolated", "transit_gateway", "core_network"] :
    role => {
      for az in local.azs : az => [
        for name, cfg in var.subnets :
        aws_subnet.main["${name}/${az}"].id
        if cfg.role == role
      ]
    }
  }
}

# ─── Legacy alias (deprecated, use subnet_ids_by_group) ──────────────────

output "subnet_ids_by_role" {
  description = <<-EOT
    DEPRECATED: Use `subnet_ids_by_group` instead. This output is keyed by
    group NAME not by role. Will be removed in v6.
    Shape: map(group_name, list(subnet_id))
  EOT
  value = {
    for name in keys(var.subnets) : name => [
      for az in local.azs : aws_subnet.main["${name}/${az}"].id
    ]
  }
}

output "subnet_ids_by_role_by_az" {
  description = <<-EOT
    DEPRECATED: Use `subnet_ids_by_group_by_az` instead. This output is keyed by
    group NAME not by role. Will be removed in v6.
    Shape: map(group_name, map(az, subnet_id))
  EOT
  value = {
    for name in keys(var.subnets) : name => {
      for az in local.azs : az => aws_subnet.main["${name}/${az}"].id
    }
  }
}

output "subnet_cidrs_by_role_by_az" {
  description = <<-EOT
    DEPRECATED: Use `subnet_cidrs_by_group_by_az` instead. Will be removed in v6.
  EOT
  value = {
    for name in keys(var.subnets) : name => {
      for az in local.azs : az => aws_subnet.main["${name}/${az}"].cidr_block
    }
  }
}

# ─── Infrastructure Outputs ──────────────────────────────────────────────

output "nat_gateway_ids" {
  description = <<-EOT
    NAT Gateway IDs indexed by AZ. Empty map when mode = "none".
    Shape: map(az, nat_gateway_id)
  EOT
  value       = var.nat_gateway.mode == "none" ? {} : local.nat_gateway_ids
}

output "nat_public_ips" {
  description = <<-EOT
    NAT Gateway public IPs indexed by AZ (Elastic IP addresses).
    Empty when mode = "none" or connectivity_type = "private".
    Shape: map(az, public_ip)
  EOT
  value = (
    var.nat_gateway.mode == "none" || var.nat_gateway.connectivity_type == "private"
    ? {}
    : local.nat_inject_mode ? {} : {
      for az in local.nat_az_set : az => (
        try(var.nat_gateway.eip.mode, "create") == "existing"
        ? aws_nat_gateway.main["nat/${az}"].public_ip
        : aws_eip.nat["nat/${az}"].public_ip
      )
    }
  )
}

output "internet_gateway_id" {
  description = "Internet Gateway ID (created or injected). Null if no IGW needed."
  value       = local.igw_id
}

output "egress_only_igw_id" {
  description = "Egress-Only Internet Gateway ID. Null if not created."
  value       = local.eigw_id
}

output "route_table_ids_by_group_by_az" {
  description = <<-EOT
    Route table IDs indexed by subnet group name and AZ.
    Shape: map(group_name, map(az, route_table_id))
  EOT
  value = {
    for name in keys(var.subnets) : name => {
      for az in local.azs : az => local.route_table_id_by_subnet["${name}/${az}"]
    }
  }
}

output "route_table_ids_by_semantic_role" {
  description = <<-EOT
    Route table IDs grouped by semantic role.
    Shape: map(role, list(route_table_id))
  EOT
  value = {
    for role in ["public", "private", "isolated", "transit_gateway", "core_network"] :
    role => flatten([
      for name, cfg in var.subnets : [
        for az in local.azs : local.route_table_id_by_subnet["${name}/${az}"]
      ] if cfg.role == role
    ])
  }
}

output "transit_gateway_attachment_id" {
  description = "Transit Gateway VPC Attachment ID, or null when no transit_gateway subnet group is configured."
  value       = try(aws_ec2_transit_gateway_vpc_attachment.this["vpc"].id, null)
}

output "core_network_attachment_id" {
  description = "Cloud WAN Core Network VPC Attachment ID, or null when no core_network subnet group is configured."
  value       = try(aws_networkmanager_vpc_attachment.this["vpc"].id, null)
}

output "flow_log_ids" {
  description = "VPC Flow Log IDs indexed by the stable flow_logs map key."
  value = {
    for name, flow_log in aws_flow_log.this : name => flow_log.id
  }
}

output "flow_log_destination_arns" {
  description = "VPC Flow Log destination ARNs indexed by the stable flow_logs map key."
  value       = local.flow_log_destination_arns
}

output "flow_log_role_arns" {
  description = "VPC Flow Log CloudWatch delivery role ARNs indexed by key; null for S3 and Firehose destinations."
  value       = local.flow_log_role_arns
}

output "vpc_lattice_service_network_association_id" {
  description = "VPC Lattice Service Network VPC association ID, or null when disabled."
  value       = try(aws_vpclattice_service_network_vpc_association.this["vpc"].id, null)
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
    internet_gateway             = local.create_igw ? aws_internet_gateway.main[0] : null
    egress_only_internet_gateway = local.create_eigw ? aws_egress_only_internet_gateway.main[0] : null
    nat_gateways = {
      for key, nat in aws_nat_gateway.main : key => {
        id                = nat.id
        allocation_id     = nat.allocation_id
        connectivity_type = nat.connectivity_type
        subnet_id         = nat.subnet_id
        public_ip         = nat.public_ip
        private_ip        = nat.private_ip
      }
    }
    eips = {
      for key, eip in aws_eip.nat : key => {
        id            = eip.id
        allocation_id = eip.allocation_id
        public_ip     = eip.public_ip
      }
    }
    route_tables = {
      for key, id in local.route_table_id_by_subnet : key => {
        id       = id
        injected = local.subnet_map[key].route_table_id != null
      }
    }
    transit_gateway_attachment = try(aws_ec2_transit_gateway_vpc_attachment.this["vpc"], null)
    core_network_attachment    = try(aws_networkmanager_vpc_attachment.this["vpc"], null)
    flow_logs                  = aws_flow_log.this
    flow_log_destinations      = aws_cloudwatch_log_group.flow_logs
    flow_log_roles             = aws_iam_role.flow_logs
    flow_log_role_policies     = aws_iam_role_policy.flow_logs
    vpc_lattice_association    = try(aws_vpclattice_service_network_vpc_association.this["vpc"], null)
    secondary_cidr_associations = {
      for key, assoc in aws_vpc_ipv4_cidr_block_association.secondary : key => {
        id         = assoc.id
        cidr_block = assoc.cidr_block
      }
    }
  }
}
