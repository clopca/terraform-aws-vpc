# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Output contract
#
# Tier 1 — Stable handles: semver-protected names, collection keys, and value
# shapes. Additive keys are allowed in minor releases; removals or type changes
# require a major release.
#
# Tier 2 — Deprecated v4 aliases: exact v4 collection keys and full-provider-
# object values. These aliases exist for downstream migration during v5 and are
# removed in v6. Provider object attributes are controlled by the AWS provider.
#
# Tier 3 — Escape hatch: complete internal resource objects. No semver guarantee;
# use only when no Tier 1 handle covers the integration.
# ─────────────────────────────────────────────────────────────────────────────

# ═══════════════════════════════════════════════════════════════════════════════
# TIER 1 — STABLE CONTRACT (semver-protected)
# ═══════════════════════════════════════════════════════════════════════════════

output "vpc_id" {
  description = "The ID of the VPC (created or referenced)."
  value       = local.vpc_id
}

output "vpc_arn" {
  description = "The ARN of the VPC (created or referenced)."
  value       = var.vpc.create ? aws_vpc.main[0].arn : data.aws_vpc.existing[0].arn
}

output "vpc_cidr_block" {
  description = "The primary IPv4 CIDR block of the VPC."
  value       = local.vpc_cidr
}

output "vpc_ipv6_cidr_block" {
  description = "The IPv6 CIDR block used for deterministic subnet /64 allocation, or null when IPv6 is disabled."
  value       = local.vpc_ipv6_cidr
}

output "azs" {
  description = "List of Availability Zones where subnets were created."
  value       = local.azs
}

# ─── Subnets by group name (the caller's stable map key) ──────────────────

output "subnet_ids_by_group" {
  description = "Subnet IDs by group. Shape: map(group_name, list(subnet_id))."
  value = {
    for name in sort(keys(var.subnets)) : name => [
      for az in local.azs : aws_subnet.main["${name}/${az}"].id
    ]
  }
}

output "subnet_ids_by_group_by_az" {
  description = "Subnet IDs by group and AZ. Shape: map(group_name, map(az, subnet_id))."
  value = {
    for name in sort(keys(var.subnets)) : name => {
      for az in local.azs : az => aws_subnet.main["${name}/${az}"].id
    }
  }
}

output "subnet_cidrs_by_group" {
  description = "Subnet IPv4 CIDRs by group. Shape: map(group_name, list(cidr|null))."
  value = {
    for name in sort(keys(var.subnets)) : name => [
      for az in local.azs : aws_subnet.main["${name}/${az}"].cidr_block
    ]
  }
}

output "subnet_cidrs_by_group_by_az" {
  description = "Subnet IPv4 CIDRs by group and AZ. Shape: map(group_name, map(az, cidr|null))."
  value = {
    for name in sort(keys(var.subnets)) : name => {
      for az in local.azs : az => aws_subnet.main["${name}/${az}"].cidr_block
    }
  }
}

output "subnet_ipv6_cidrs_by_group_by_az" {
  description = "Subnet IPv6 CIDRs by group and AZ. Shape: map(group_name, map(az, cidr|null))."
  value = {
    for name in sort(keys(var.subnets)) : name => {
      for az in local.azs : az => aws_subnet.main["${name}/${az}"].ipv6_cidr_block
    }
  }
}

output "subnet_arns_by_group_by_az" {
  description = "Subnet ARNs by group and AZ. Shape: map(group_name, map(az, arn))."
  value = {
    for name in sort(keys(var.subnets)) : name => {
      for az in local.azs : az => aws_subnet.main["${name}/${az}"].arn
    }
  }
}

# ─── Subnets by semantic role ─────────────────────────────────────────────
# All groups sharing a role are aggregated. The per-AZ variants return lists
# because v5 permits multiple groups with the same semantic role.

output "subnet_ids_by_semantic_role" {
  description = "Subnet IDs by semantic role. Shape: map(role, list(subnet_id))."
  value = {
    for role in ["public", "private", "isolated", "transit_gateway", "core_network"] :
    role => flatten([
      for name in sort(keys(var.subnets)) : [
        for az in local.azs : aws_subnet.main["${name}/${az}"].id
      ] if var.subnets[name].role == role
    ])
  }
}

output "subnet_ids_by_semantic_role_by_az" {
  description = "Subnet IDs by semantic role and AZ. Shape: map(role, map(az, list(subnet_id)))."
  value = {
    for role in ["public", "private", "isolated", "transit_gateway", "core_network"] :
    role => {
      for az in local.azs : az => [
        for name in sort(keys(var.subnets)) : aws_subnet.main["${name}/${az}"].id
        if var.subnets[name].role == role
      ]
    }
  }
}

output "subnet_cidrs_by_semantic_role" {
  description = "Subnet IPv4 CIDRs by semantic role. Shape: map(role, list(cidr|null))."
  value = {
    for role in ["public", "private", "isolated", "transit_gateway", "core_network"] :
    role => flatten([
      for name in sort(keys(var.subnets)) : [
        for az in local.azs : aws_subnet.main["${name}/${az}"].cidr_block
      ] if var.subnets[name].role == role
    ])
  }
}

output "subnet_cidrs_by_semantic_role_by_az" {
  description = "Subnet IPv4 CIDRs by semantic role and AZ. Shape: map(role, map(az, list(cidr|null)))."
  value = {
    for role in ["public", "private", "isolated", "transit_gateway", "core_network"] :
    role => {
      for az in local.azs : az => [
        for name in sort(keys(var.subnets)) : aws_subnet.main["${name}/${az}"].cidr_block
        if var.subnets[name].role == role
      ]
    }
  }
}

# ─── Route tables ─────────────────────────────────────────────────────────

output "route_table_ids_by_group" {
  description = "Route table IDs by subnet group. Shape: map(group_name, list(route_table_id))."
  value = {
    for name in sort(keys(var.subnets)) : name => [
      for az in local.azs : local.route_table_id_by_subnet["${name}/${az}"]
    ]
  }
}

output "route_table_ids_by_group_by_az" {
  description = "Route table IDs by subnet group and AZ. Shape: map(group_name, map(az, route_table_id))."
  value = {
    for name in sort(keys(var.subnets)) : name => {
      for az in local.azs : az => local.route_table_id_by_subnet["${name}/${az}"]
    }
  }
}

output "route_table_ids_by_semantic_role" {
  description = "Route table IDs by semantic role. Shape: map(role, list(route_table_id))."
  value = {
    for role in ["public", "private", "isolated", "transit_gateway", "core_network"] :
    role => flatten([
      for name in sort(keys(var.subnets)) : [
        for az in local.azs : local.route_table_id_by_subnet["${name}/${az}"]
      ] if var.subnets[name].role == role
    ])
  }
}

output "route_table_ids_by_semantic_role_by_az" {
  description = "Route table IDs by semantic role and AZ. Shape: map(role, map(az, list(route_table_id)))."
  value = {
    for role in ["public", "private", "isolated", "transit_gateway", "core_network"] :
    role => {
      for az in local.azs : az => [
        for name in sort(keys(var.subnets)) : local.route_table_id_by_subnet["${name}/${az}"]
        if var.subnets[name].role == role
      ]
    }
  }
}

# ─── NAT and gateways ─────────────────────────────────────────────────────

output "nat_gateway_ids" {
  description = "NAT Gateway IDs by AZ. Empty when nat_gateway.mode is none. Shape: map(az, nat_gateway_id)."
  value       = var.nat_gateway.mode == "none" ? {} : local.nat_gateway_ids
}

output "nat_public_ips" {
  description = "Created public NAT Gateway public IPs by AZ. Empty for injected or private NAT Gateways."
  value = (
    var.nat_gateway.mode == "none" || var.nat_gateway.connectivity_type == "private" || local.nat_inject_mode
    ? {}
    : { for key, nat in aws_nat_gateway.main : split("/", key)[1] => nat.public_ip }
  )
}

output "nat_private_ips" {
  description = "Created NAT Gateway private IPs by AZ. Empty when NAT Gateways are injected."
  value = local.nat_inject_mode ? {} : {
    for key, nat in aws_nat_gateway.main : split("/", key)[1] => nat.private_ip
  }
}

output "nat_eip_allocation_ids" {
  description = "Created or caller-supplied EIP allocation IDs by AZ for public NAT Gateways. Empty for injected/private NAT Gateways."
  value = (
    var.nat_gateway.mode == "none" || var.nat_gateway.connectivity_type == "private" || local.nat_inject_mode
    ? {}
    : { for key, nat in aws_nat_gateway.main : split("/", key)[1] => nat.allocation_id }
  )
}

output "internet_gateway_id" {
  description = "Internet Gateway ID (created or injected), or null when no IGW is needed."
  value       = local.igw_id
}

output "egress_only_igw_id" {
  description = "Egress-only Internet Gateway ID, or null when not created."
  value       = local.eigw_id
}

# ─── Attachments, Flow Logs, and VPC Lattice ─────────────────────────────

output "transit_gateway_attachment_id" {
  description = "Transit Gateway VPC attachment ID, or null when the role is absent."
  value       = try(aws_ec2_transit_gateway_vpc_attachment.this["vpc"].id, null)
}

output "core_network_attachment_id" {
  description = "Cloud WAN Core Network VPC attachment ID, or null when the role is absent."
  value       = try(aws_networkmanager_vpc_attachment.this["vpc"].id, null)
}

output "flow_log_ids" {
  description = "VPC Flow Log IDs by the stable flow_logs map key. Shape: map(key, flow_log_id)."
  value       = { for name, flow_log in aws_flow_log.this : name => flow_log.id }
}

output "flow_log_destination_arns" {
  description = "VPC Flow Log destination ARNs by stable flow_logs map key."
  value       = local.flow_log_destination_arns
}

output "flow_log_role_arns" {
  description = "CloudWatch delivery role ARNs by flow-log key; null for S3 and Firehose."
  value       = local.flow_log_role_arns
}

output "vpc_lattice_service_network_association_id" {
  description = "VPC Lattice Service Network VPC association ID, or null when disabled."
  value       = try(aws_vpclattice_service_network_vpc_association.this["vpc"].id, null)
}

# ═══════════════════════════════════════════════════════════════════════════════
# TIER 2 — DEPRECATED v4-COMPATIBLE ALIASES (removed in v6)
#
# Names, outer collection keys, and full-object/scalar shapes match v4 outputs.
# For exact compatibility, keep migrated reserved group names `public`,
# `transit_gateway`, and `core_network`, and use `default` as the migrated v4
# Flow Log key. Prefer Tier 1 for all new integrations.
# ═══════════════════════════════════════════════════════════════════════════════

output "vpc_attributes" {
  description = "DEPRECATED: v4-compatible full VPC object. Use vpc_id/vpc_arn/vpc_cidr_block. Removed in v6."
  value       = local.create_vpc ? aws_vpc.main[0] : data.aws_vpc.existing[0]
}

output "private_subnet_attributes_by_az" {
  description = "DEPRECATED: v4-compatible map of full private subnet objects keyed '<group>/<az>'. Use Tier 1 subnet outputs. Removed in v6."
  value = {
    for key, subnet in aws_subnet.main : key => subnet
    if !contains(["public", "transit_gateway", "core_network"], split("/", key)[0])
  }
}

output "public_subnet_attributes_by_az" {
  description = "DEPRECATED: v4-compatible map of full public subnet objects keyed by AZ. Use Tier 1 subnet outputs. Removed in v6."
  value = contains(keys(var.subnets), "public") ? {
    for az in local.azs : az => aws_subnet.main["public/${az}"]
  } : {}
}

output "tgw_subnet_attributes_by_az" {
  description = "DEPRECATED: v4-compatible map of full TGW subnet objects keyed by AZ. Use Tier 1 subnet outputs. Removed in v6."
  value = contains(keys(var.subnets), "transit_gateway") ? {
    for az in local.azs : az => aws_subnet.main["transit_gateway/${az}"]
  } : {}
}

output "core_network_subnet_attributes_by_az" {
  description = "DEPRECATED: v4-compatible map of full Cloud WAN subnet objects keyed by AZ. Use Tier 1 subnet outputs. Removed in v6."
  value = contains(keys(var.subnets), "core_network") ? {
    for az in local.azs : az => aws_subnet.main["core_network/${az}"]
  } : {}
}

output "rt_attributes_by_type_by_az" {
  description = "DEPRECATED: v4-compatible full route-table objects keyed type then AZ or '<group>/<az>' for private. Use Tier 1 route table IDs. Removed in v6."
  value = {
    private = {
      for key, route_table in aws_route_table.main : key => route_table
      if !contains(["public", "transit_gateway", "core_network"], split("/", key)[0])
    }
    public = contains(keys(var.subnets), "public") ? {
      for az in local.azs : az => aws_route_table.main["public/${az}"]
      if var.subnets.public.manage_route_table
    } : {}
    transit_gateway = contains(keys(var.subnets), "transit_gateway") ? {
      for az in local.azs : az => aws_route_table.main["transit_gateway/${az}"]
      if var.subnets.transit_gateway.manage_route_table
    } : {}
    core_network = contains(keys(var.subnets), "core_network") ? {
      for az in local.azs : az => aws_route_table.main["core_network/${az}"]
      if var.subnets.core_network.manage_route_table
    } : {}
  }
}

output "nat_gateway_attributes_by_az" {
  description = "DEPRECATED: v4-compatible map of full created NAT Gateway objects keyed by AZ. Use nat_gateway_ids/nat_*_ips. Removed in v6."
  value = {
    for key, nat_gateway in aws_nat_gateway.main : split("/", key)[1] => nat_gateway
  }
}

output "natgw_id_per_az" {
  description = "DEPRECATED: v4-compatible map(az, object({id=string})); duplicates the selected ID in single_az mode. Use nat_gateway_ids. Removed in v6."
  value = var.nat_gateway.mode == "none" ? {} : {
    for az in local.azs : az => {
      id = local.nat_gateway_ids[var.nat_gateway.mode == "single_az" ? var.nat_gateway.az : az]
    }
  }
}

output "internet_gateway" {
  description = "DEPRECATED: v4-compatible full created Internet Gateway object. Use internet_gateway_id. Removed in v6."
  value       = local.create_igw ? aws_internet_gateway.main[0] : null
}

output "egress_only_internet_gateway" {
  description = "DEPRECATED: v4-compatible full Egress-only Internet Gateway object. Use egress_only_igw_id. Removed in v6."
  value       = local.create_eigw ? aws_egress_only_internet_gateway.main[0] : null
}

output "core_network_attachment" {
  description = "DEPRECATED: v4-compatible full Cloud WAN attachment object. Use core_network_attachment_id. Removed in v6."
  value       = try(aws_networkmanager_vpc_attachment.this["vpc"], null)
}

output "vpc_lattice_service_network_association" {
  description = "DEPRECATED: v4-compatible full VPC Lattice association object. Use vpc_lattice_service_network_association_id. Removed in v6."
  value       = try(aws_vpclattice_service_network_vpc_association.this["vpc"], null)
}

output "flow_log_attributes" {
  description = "DEPRECATED: v4-compatible single full Flow Log object. Uses key 'default', or the only configured Flow Log. Use flow_log_ids. Removed in v6."
  value       = try(aws_flow_log.this["default"], one(values(aws_flow_log.this)), null)
}

# Pre-publication aliases from the Phase 1 prototype. They are not v4 outputs,
# but remain during v5 so early prototype consumers can migrate without churn.
output "subnet_ids_by_role" {
  description = "DEPRECATED: prototype alias keyed by group name. Use subnet_ids_by_group. Removed in v6."
  value = {
    for name in sort(keys(var.subnets)) : name => [
      for az in local.azs : aws_subnet.main["${name}/${az}"].id
    ]
  }
}

output "subnet_ids_by_role_by_az" {
  description = "DEPRECATED: prototype alias keyed by group name. Use subnet_ids_by_group_by_az. Removed in v6."
  value = {
    for name in sort(keys(var.subnets)) : name => {
      for az in local.azs : az => aws_subnet.main["${name}/${az}"].id
    }
  }
}

output "subnet_cidrs_by_role_by_az" {
  description = "DEPRECATED: prototype alias keyed by group name. Use subnet_cidrs_by_group_by_az. Removed in v6."
  value = {
    for name in sort(keys(var.subnets)) : name => {
      for az in local.azs : az => aws_subnet.main["${name}/${az}"].cidr_block
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# TIER 3 — ESCAPE HATCH (complete objects, NO semver guarantee)
# ═══════════════════════════════════════════════════════════════════════════════

output "resources" {
  description = "UNSTABLE: complete internal resource objects for advanced composition. Shape may change in any release; prefer Tier 1."
  value = {
    vpc = {
      created  = aws_vpc.main
      existing = data.aws_vpc.existing
    }
    secondary_cidr_associations = aws_vpc_ipv4_cidr_block_association.secondary
    subnets                     = aws_subnet.main
    route_tables                = aws_route_table.main
    injected_route_table_ids = {
      for name, cfg in var.subnets : name => cfg.route_table_id
      if !cfg.manage_route_table
    }
    route_table_associations     = aws_route_table_association.main
    internet_gateway             = aws_internet_gateway.main
    egress_only_internet_gateway = aws_egress_only_internet_gateway.main
    eips                         = aws_eip.nat
    nat_gateways                 = aws_nat_gateway.main
    transit_gateway_attachments  = aws_ec2_transit_gateway_vpc_attachment.this
    core_network_attachments     = aws_networkmanager_vpc_attachment.this
    core_network_accepters       = aws_networkmanager_attachment_accepter.this
    flow_logs                    = aws_flow_log.this
    flow_log_destinations        = aws_cloudwatch_log_group.flow_logs
    flow_log_roles               = aws_iam_role.flow_logs
    flow_log_role_policies       = aws_iam_role_policy.flow_logs
    vpc_lattice_associations     = aws_vpclattice_service_network_vpc_association.this
    routes = {
      igw_ipv4  = aws_route.igw_ipv4
      igw_ipv6  = aws_route.igw_ipv6
      nat       = aws_route.nat
      nat64     = aws_route.nat64
      eigw      = aws_route.eigw
      tgw       = aws_route.tgw
      tgw_ipv6  = aws_route.tgw_ipv6
      cwan      = aws_route.cwan
      cwan_ipv6 = aws_route.cwan_ipv6
    }
  }
}
