# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Subnet Engine (locals.tf)
#
# CIDR Assignment Strategy:
#   1. EXPLICIT cidrs_by_az (first-class): caller maps each AZ to its CIDR — used as-is.
#   2. IPAM: ipam_pool_id + netmask_length — AWS allocates at apply time.
#   3. NETMASK (calculated): deterministic derivation from VPC CIDR.
#
# ═══════════════════════════════════════════════════════════════════════════════
# DETERMINISTIC CIDR CALCULATION — STABILITY PROOF [R1-C2]
# ═══════════════════════════════════════════════════════════════════════════════
#
# Algorithm (two-tier with fixed six-AZ reservations):
#
#   TIER 1 — PINNED GROUPS (cidr_index set):
#     `cidr_index` selects an absolute group slot at that group's netmask. Each
#     slot reserves six AZ-sized CIDRs. Pins are immune to additions/removals;
#     overlapping absolute ranges across different netmasks are rejected.
#
#   TIER 2 — UNPINNED GROUPS (cidr_index = null):
#     Remaining groups are packed after all pinned ranges, sorted by:
#       1. Netmask ascending (larger subnets first)
#       2. Group key alphabetically within the same netmask
#     Every group also reserves six AZ positions.
#
# STABILITY GUARANTEES:
#
#   Scenario 1: Add unpinned "beta" to existing /24 ["alpha", "gamma"]
#     Before: alpha=slots 0..5, gamma=slots 6..11
#     After:  alpha=slots 0..5, beta=slots 6..11, gamma=slots 12..17
#     ⚠️ gamma shifts because it sorts after the inserted unpinned group.
#
#   Scenario 2: alpha has cidr_index=0, gamma has cidr_index=5
#     Before: alpha=slots 0..5, gamma=slots 30..35
#     After:  alpha=slots 0..5, gamma=slots 30..35, beta=slots 36..41
#     ✅ Neither pinned group shifts; beta starts after all pinned ranges.
#
#   Scenario 3: Remove "beta" from unpinned ["alpha", "beta", "gamma"]
#     Before: alpha=slots 0..5, beta=slots 6..11, gamma=slots 12..17
#     After:  alpha=slots 0..5, gamma=slots 6..11
#     ⚠️ gamma shifts. Use pinning or explicit CIDRs for immutable allocations.
#
#   Scenario 4: Add an AZ to an existing 2-AZ deployment
#     Each group already reserves six AZ slots, so the new AZ consumes the next
#     slot in that group. Existing AZ CIDRs remain unchanged.
#
# PRODUCTION RECOMMENDATION:
#   Use explicit `cidrs_by_az` for any subnet group that must never shift.
#   Use `cidr_index` when deterministic six-AZ reservations are appropriate.
#   Use bare `netmask` only when shifts after group mutations are acceptable.
#
# State Key Format: "${subnet_group_name}/${az}" for ALL resources.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # ─── AZ Resolution ───────────────────────────────────────────────────────
  # When `names` is provided, use directly. When `count` is used, we rely on
  # the data source (defined in main.tf) to get region AZs.
  # Count mode sorts the discovery result and takes exactly the requested
  # prefix. Explicit names preserve caller order as part of the CIDR contract.
  discovered_azs = var.availability_zones.names != null ? [] : sort(data.aws_availability_zones.current[0].names)
  azs = var.availability_zones.names != null ? var.availability_zones.names : slice(
    local.discovered_azs,
    0,
    min(var.availability_zones.count, length(local.discovered_azs)),
  )

  # ─── VPC Identity ───────────────────────────────────────────────────────
  create_vpc = var.vpc.create
  vpc_id     = local.create_vpc ? aws_vpc.main[0].id : var.vpc.id

  # Primary CIDRs — needed for deterministic subnet calculation.
  vpc_cidr = local.create_vpc ? aws_vpc.main[0].cidr_block : data.aws_vpc.existing[0].cidr_block
  vpc_ipv6_cidr = var.addressing.ipv6 == null ? null : (
    local.create_vpc ? aws_vpc.main[0].ipv6_cidr_block : try(sort([
      for association in data.aws_vpc.existing[0].ipv6_cidr_block_associations : association.ipv6_cidr_block
      if association.state == "associated" && (
        var.addressing.ipv6.association_id == null || try(association.association_id, null) == var.addressing.ipv6.association_id
      )
    ])[0], null)
  )

  # ─── Subnet Group Classification ────────────────────────────────────────
  # Groups by addressing mode
  subnets_with_netmask = {
    for k, v in var.subnets : k => v if v.ipv4 != null && v.ipv4.netmask != null
  }
  subnets_with_cidrs_by_az = {
    for k, v in var.subnets : k => v if v.ipv4 != null && v.ipv4.cidrs_by_az != null
  }
  # ─── Deterministic CIDR Calculation with Pinning [R1-C2] ───────────────
  #
  # Two-tier allocation:
  #   1. Pinned groups (cidr_index != null) — reserved slots, immune to changes
  #   2. Unpinned groups — sequential after highest pinned slot, alphabetical

  vpc_prefix_length = tonumber(split("/", local.vpc_cidr)[1])

  # Calculated groups reserve the contract maximum of six AZ slots. The fixed
  # stride makes AZ expansion append-only instead of multiplying offsets by the
  # current AZ count and shifting every later group.
  cidr_az_stride = 6

  # Normalize every allocation to /28 units. This lets differently sized
  # netmasks share one non-overlapping address space while cidr_index remains an
  # absolute group slot at the configured netmask.
  cidr_units_per_group = {
    for name, cfg in local.subnets_with_netmask :
    name => local.cidr_az_stride * pow(2, 28 - cfg.ipv4.netmask)
  }

  pinned_group_start_unit = {
    for name, cfg in local.subnets_with_netmask :
    name => cfg.ipv4.cidr_index * local.cidr_units_per_group[name]
    if cfg.ipv4.cidr_index != null
  }


  pinned_group_names_sorted = sort(keys(local.pinned_group_start_unit))
  pinned_group_overlap_pairs = flatten([
    for name in local.pinned_group_names_sorted : [
      for other in local.pinned_group_names_sorted : "${name}/${other}"
      if index(local.pinned_group_names_sorted, name) < index(local.pinned_group_names_sorted, other) &&
      local.pinned_group_start_unit[name] <= local.pinned_group_end_unit[other] &&
      local.pinned_group_start_unit[other] <= local.pinned_group_end_unit[name]
    ]
  ])
  pinned_group_end_unit = {
    for name, start in local.pinned_group_start_unit :
    name => start + local.cidr_units_per_group[name] - 1
  }

  # Pinned groups reserve absolute ranges first. All unpinned groups are packed
  # after the highest pinned /28 unit, ordered by larger subnet first and then
  # group name. Because sizes descend, one initial alignment is sufficient.
  pinned_reserved_units = length(local.pinned_group_end_unit) == 0 ? 0 : max(values(local.pinned_group_end_unit)...) + 1

  unpinned_group_order = sort([
    for name, cfg in local.subnets_with_netmask :
    format("%02d|%s", cfg.ipv4.netmask, name)
    if cfg.ipv4.cidr_index == null
  ])

  first_unpinned_group = try(split("|", local.unpinned_group_order[0])[1], null)
  unpinned_base_unit = local.first_unpinned_group == null ? local.pinned_reserved_units : (
    ceil(local.pinned_reserved_units / local.cidr_units_per_group[local.first_unpinned_group]) *
    local.cidr_units_per_group[local.first_unpinned_group]
  )

  unpinned_group_start_unit = {
    for entry in local.unpinned_group_order : split("|", entry)[1] => (
      local.unpinned_base_unit + sum(concat([0], [
        for prior in local.unpinned_group_order :
        local.cidr_units_per_group[split("|", prior)[1]]
        if index(local.unpinned_group_order, prior) < index(local.unpinned_group_order, entry)
      ]))
    )
  }

  calculated_group_start_unit = merge(
    local.pinned_group_start_unit,
    local.unpinned_group_start_unit,
  )

  # Materialize one CIDR per configured AZ. Each group's remaining reserved AZ
  # slots stay unused, preserving all existing CIDRs when a new AZ is appended.
  calculated_cidrs = merge([
    for name, cfg in local.subnets_with_netmask : {
      for ai, az in local.azs : "${name}/${az}" => try(cidrsubnet(
        local.vpc_cidr,
        cfg.ipv4.netmask - local.vpc_prefix_length,
        (local.calculated_group_start_unit[name] / pow(2, 28 - cfg.ipv4.netmask)) + ai,
      ), local.vpc_cidr)
    }
  ]...)
  invalid_calculated_ipv4_keys = [
    for name, cfg in local.subnets_with_netmask : name
    if !alltrue([
      for ai, az in local.azs : can(cidrsubnet(
        local.vpc_cidr,
        cfg.ipv4.netmask - local.vpc_prefix_length,
        (local.calculated_group_start_unit[name] / pow(2, 28 - cfg.ipv4.netmask)) + ai,
      ))
    ])
  ]
  calculated_group_end_unit = {
    for name, start in local.calculated_group_start_unit :
    name => start + local.cidr_units_per_group[name] - 1
  }
  available_cidr_units = pow(2, 28 - local.vpc_prefix_length)
  capacity_exceeded_ipv4_groups = [
    for name, end in local.calculated_group_end_unit : name
    if end >= local.available_cidr_units
  ]

  # ─── Deterministic IPv6 /64 calculation ───────────────────────────────
  # All AWS IPv6 subnets are /64. The engine mirrors IPv4 state stability:
  # six AZ slots per group, absolute pinned group slots, then alphabetical
  # packing of unpinned groups after the highest pin.
  subnets_with_calculated_ipv6 = {
    for name, cfg in var.subnets : name => cfg
    if cfg.ipv6 != null && cfg.ipv6.cidrs_by_az == null && cfg.ipv6.netmask_length == null && cfg.ipv6.auto_assign
  }

  ipv6_pinned_group_start = {
    for name, cfg in local.subnets_with_calculated_ipv6 :
    name => cfg.ipv6.cidr_index * local.cidr_az_stride
    if cfg.ipv6.cidr_index != null
  }
  ipv6_pinned_reserved_slots = length(local.ipv6_pinned_group_start) == 0 ? 0 : max([
    for start in values(local.ipv6_pinned_group_start) : start + local.cidr_az_stride
  ]...)
  ipv6_unpinned_group_order = sort([
    for name, cfg in local.subnets_with_calculated_ipv6 : name
    if cfg.ipv6.cidr_index == null
  ])
  ipv6_calculated_group_start = merge(
    local.ipv6_pinned_group_start,
    {
      for name in local.ipv6_unpinned_group_order :
      name => local.ipv6_pinned_reserved_slots + index(local.ipv6_unpinned_group_order, name) * local.cidr_az_stride
    },
  )
  vpc_ipv6_prefix_length = local.vpc_ipv6_cidr == null ? null : tonumber(split("/", local.vpc_ipv6_cidr)[1])
  calculated_ipv6_cidrs = merge([
    for name, cfg in local.subnets_with_calculated_ipv6 : {
      for ai, az in local.azs : "${name}/${az}" => try(cidrsubnet(
        local.vpc_ipv6_cidr,
        64 - local.vpc_ipv6_prefix_length,
        local.ipv6_calculated_group_start[name] + ai,
      ), local.vpc_ipv6_cidr)
    }
  ]...)
  invalid_calculated_ipv6_keys = [
    for name, cfg in local.subnets_with_calculated_ipv6 : name
    if !alltrue([
      for ai, az in local.azs : can(cidrsubnet(
        local.vpc_ipv6_cidr,
        64 - local.vpc_ipv6_prefix_length,
        local.ipv6_calculated_group_start[name] + ai,
      ))
    ])
  ]

  # ─── Routing: resolve internet_gateway default [R2-H3] ──────────────────
  # null = auto: true for public role, false for everything else
  resolved_routing = {
    for name, cfg in var.subnets : name => {
      nat_gateway     = try(cfg.routing.nat_gateway, false)
      egress_only_igw = try(cfg.routing.egress_only_igw, false)
      internet_gateway = coalesce(
        try(cfg.routing.internet_gateway, null),
        cfg.role == "public" ? true : false
      )
      dns64                            = try(cfg.routing.dns64, false)
      transit_gateway                  = try(cfg.routing.transit_gateway, null)
      transit_gateway_ipv6             = try(cfg.routing.transit_gateway_ipv6, null)
      transit_gateway_attachments      = try(cfg.routing.transit_gateway_attachments, {})
      transit_gateway_attachments_ipv6 = try(cfg.routing.transit_gateway_attachments_ipv6, {})
      core_network                     = try(cfg.routing.core_network, null)
      core_network_ipv6                = try(cfg.routing.core_network_ipv6, null)
      s3_gateway_endpoint              = try(cfg.routing.s3_gateway_endpoint, false)
      dynamodb_gateway_endpoint        = try(cfg.routing.dynamodb_gateway_endpoint, false)
    }
  }

  subnet_connectivity_by_group_by_az = {
    for name, routing in local.resolved_routing : name => {
      for az in local.azs : az => {
        igw  = routing.internet_gateway
        nat  = routing.nat_gateway || routing.dns64
        eigw = routing.egress_only_igw
        tgw = (
          length(coalesce(routing.transit_gateway, [])) > 0 ||
          length(coalesce(routing.transit_gateway_ipv6, [])) > 0 ||
          anytrue([for destinations in values(routing.transit_gateway_attachments) : length(destinations) > 0]) ||
          anytrue([for destinations in values(routing.transit_gateway_attachments_ipv6) : length(destinations) > 0])
        )
        core_network = (
          length(coalesce(routing.core_network, [])) > 0 ||
          length(coalesce(routing.core_network_ipv6, [])) > 0
        )
        s3_gateway_endpoint       = routing.s3_gateway_endpoint
        dynamodb_gateway_endpoint = routing.dynamodb_gateway_endpoint
        internet = (
          routing.internet_gateway || routing.nat_gateway || routing.dns64 || routing.egress_only_igw
        )
      }
    }
  }

  # ─── IGW: plan-known create-or-inject ───────────────────────────────────
  # Public role is only the default for resolved routing; an explicit false is
  # authoritative. A public NAT created by this module still requires an IGW.
  needs_igw = (
    anytrue([for name, routing in local.resolved_routing : routing.internet_gateway]) ||
    (var.nat_gateway.mode != "none" && var.nat_gateway.create && var.nat_gateway.connectivity_type == "public")
  )
  create_igw = local.needs_igw && var.vpc.igw_create
  igw_id = !local.needs_igw ? null : (
    local.create_igw ? try(aws_internet_gateway.main[0].id, null) : var.vpc.igw_id
  )

  # ─── Flat Subnet Map: "name/az" → config ────────────────────────────────
  # This is the master map that drives aws_subnet.main for_each.
  # Every subnet instance has a unique key "subnet_name/az".

  subnet_map = merge([
    for name, cfg in var.subnets : {
      for ai, az in local.azs : "${name}/${az}" => {
        name        = name
        az          = az
        role        = cfg.role
        create      = cfg.create
        existing_id = try(cfg.existing_ids[az], null)
        name_prefix = coalesce(cfg.name_prefix, name)
        resource_name = replace(replace(replace(
          coalesce(cfg.name_format, "{vpc}-{group}-{az}"),
          "{vpc}", var.vpc.name), "{group}", coalesce(cfg.name_prefix, name)), "{az}", az
        )
        route_table_name = replace(replace(replace(
          coalesce(cfg.route_table_name_format, cfg.name_format, "{vpc}-{group}-{az}"),
          "{vpc}", var.vpc.name), "{group}", coalesce(cfg.name_prefix, name)), "{az}", az
        )
        tags               = cfg.tags
        manage_route_table = cfg.manage_route_table
        route_table_key    = cfg.route_table_key
        route_table_id     = cfg.route_table_id

        # CIDR resolution: explicit > calculated > IPAM (null, resolved at apply)
        cidr_block = (
          cfg.ipv4 != null && cfg.ipv4.cidrs_by_az != null ? try(cfg.ipv4.cidrs_by_az[az], null) :
          cfg.ipv4 != null && cfg.ipv4.netmask != null ? local.calculated_cidrs["${name}/${az}"] :
          null # IPAM or ipv6-only
        )

        # IPAM fields (null when not using IPAM for this subnet)
        ipam_pool_id       = try(cfg.ipv4.ipam_pool_id, null)
        netmask_length     = try(cfg.ipv4.netmask_length, null)
        secondary_cidr_key = try(cfg.ipv4.secondary_cidr_key, null)

        # IPv6: explicit > deterministic VPC /64 > subnet IPAM.
        ipv6_cidr = (
          try(cfg.ipv6.cidrs_by_az, null) != null ? try(cfg.ipv6.cidrs_by_az[az], null) :
          contains(keys(local.subnets_with_calculated_ipv6), name) ? local.calculated_ipv6_cidrs["${name}/${az}"] :
          null
        )
        ipv6_ipam_pool_id   = try(cfg.ipv6.ipam_pool_id, null)
        ipv6_netmask_length = try(cfg.ipv6.netmask_length, null)
        ipv6_native         = try(cfg.ipv6.native_only, false)
        assign_ipv6         = try(cfg.ipv6.auto_assign, false)

        # Routing config (carried through for phases 2+)
        routing = local.resolved_routing[name]

        # Role-specific
        map_public_ip           = cfg.role == "public" && !try(cfg.ipv6.native_only, false) ? try(cfg.public_options.map_public_ip, false) : false
        transit_gateway_options = cfg.role == "transit_gateway" ? cfg.transit_gateway_options : null
        core_network_options    = cfg.role == "core_network" ? cfg.core_network_options : null
      }
    }
  ]...)

  # ─── Secondary CIDRs and subnet create-or-inject handles ────────────────
  secondary_cidrs = var.addressing.ipv4 != null ? var.addressing.ipv4.secondary : {}
  secondary_cidrs_to_create = {
    for key, secondary in local.secondary_cidrs : key => secondary if secondary.create
  }
  secondary_cidr_association_ids = {
    for key, secondary in local.secondary_cidrs : key => (
      secondary.create ? aws_vpc_ipv4_cidr_block_association.secondary[key].id : secondary.association_id
    )
  }

  subnets_to_create = {
    for key, subnet in local.subnet_map : key => subnet if subnet.create
  }
  subnets_to_inject = {
    for key, subnet in local.subnet_map : key => subnet if !subnet.create
  }
  subnet_ids = merge(
    { for key, subnet in aws_subnet.main : key => subnet.id },
    { for key, subnet in data.aws_subnet.existing : key => subnet.id },
  )
  subnet_arns = merge(
    { for key, subnet in aws_subnet.main : key => subnet.arn },
    { for key, subnet in data.aws_subnet.existing : key => subnet.arn },
  )
  subnet_ipv4_cidrs = merge(
    { for key, subnet in aws_subnet.main : key => subnet.cidr_block },
    { for key, subnet in data.aws_subnet.existing : key => subnet.cidr_block },
  )
  subnet_ipv6_cidrs = merge(
    { for key, subnet in aws_subnet.main : key => subnet.ipv6_cidr_block },
    { for key, subnet in data.aws_subnet.existing : key => subnet.ipv6_cidr_block },
  )

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 2 — NAT GATEWAYS, EIGW, ROUTING
  # ═══════════════════════════════════════════════════════════════════════════

  # ─── NAT Gateway — AZ resolution ────────────────────────────────────────
  # Regional mode creates one VPC-level resource but retains the configured AZ
  # set for output/routing keys and manual EIP coverage.
  nat_az_set = (
    var.nat_gateway.mode == "none" ? toset([]) :
    var.nat_gateway.mode == "single_az" ? toset([var.nat_gateway.az]) :
    toset(local.azs) # all_azs or regional
  )

  nat_inject_mode = !var.nat_gateway.create
  nat_eip_mode    = try(var.nat_gateway.eip.mode, "create")

  # Tier 1 remains map(az, id). Regional mode repeats the one physical ID for
  # every configured AZ so route addresses and consumers keep stable AZ keys.
  nat_gateway_ids = var.nat_gateway.mode == "none" ? {} : (
    var.nat_gateway.mode == "regional" ? {
      for az in local.azs : az => (
        local.nat_inject_mode
        ? var.nat_gateway.existing_ids["regional"]
        : aws_nat_gateway.main["nat/regional"].id
      )
      } : (
      local.nat_inject_mode ? var.nat_gateway.existing_ids : {
        for az in local.nat_az_set : az => aws_nat_gateway.main["nat/${az}"].id
      }
    )
  )

  # Zonal Gateways require a compatible host subnet group. Regional mode is
  # VPC-level and intentionally bypasses every subnet-placement fallback.
  first_public_group = try(sort([
    for name, cfg in var.subnets : name if cfg.role == "public"
  ])[0], null)

  first_private_group = try(sort([
    for name, cfg in var.subnets : name if cfg.role == "private"
  ])[0], null)

  nat_default_host_group = (
    var.nat_gateway.connectivity_type == "private"
    ? local.first_private_group
    : local.first_public_group
  )
  nat_host_group = var.nat_gateway.mode == "regional" ? null : (
    var.nat_gateway.subnet_group != null
    ? var.nat_gateway.subnet_group
    : local.nat_default_host_group
  )
  nat_host_group_name = var.nat_gateway.mode == "regional" ? "regional" : (
    local.nat_host_group == null ? "" : coalesce(
      try(var.subnets[local.nat_host_group].name_prefix, null),
      local.nat_host_group,
    )
  )
  nat_host_group_tags = local.nat_host_group == null ? {} : try(var.subnets[local.nat_host_group].tags, {})
  nat_resource_tags   = merge(local.nat_host_group_tags, var.nat_gateway.tags)
  nat_eip_tags        = merge(local.nat_resource_tags, var.nat_gateway.eip.tags)
  nat_names = {
    for az in local.nat_az_set : az => replace(replace(replace(
      var.nat_gateway.name_format,
      "{vpc}", var.vpc.name), "{group}", local.nat_host_group_name), "{az}", az
    )
  }
  regional_nat_name = replace(replace(replace(
    var.nat_gateway.name_format,
    "{vpc}", var.vpc.name), "{group}", "regional"), "{az}", "regional"
  )
  nat_eip_names = {
    for az in local.nat_az_set : az => replace(replace(replace(
      coalesce(var.nat_gateway.eip.name_format, var.nat_gateway.name_format),
      "{vpc}", var.vpc.name), "{group}", local.nat_host_group_name), "{az}", az
    )
  }

  # Zonal create/byoip_pool creates EIPs. Regional create is AWS automatic mode
  # (no child aws_eip); regional byoip_pool creates one EIP per configured AZ for
  # manual availability_zone_address blocks.
  nat_eips_to_create = (
    !local.nat_inject_mode &&
    var.nat_gateway.connectivity_type == "public" &&
    (
      var.nat_gateway.mode == "regional"
      ? local.nat_eip_mode == "byoip_pool"
      : local.nat_eip_mode != "existing"
    )
    ) ? {
    for az in local.nat_az_set : "nat/${az}" => {
      az   = az
      name = local.nat_eip_names[az]
      tags = local.nat_eip_tags
    }
  } : {}

  regional_nat_availability_zone_addresses = (
    var.nat_gateway.mode == "regional" && local.nat_eip_mode != "create"
    ) ? {
    for az in local.azs : az => toset([
      local.nat_eip_mode == "existing"
      ? var.nat_gateway.eip.allocation_ids[az]
      : aws_eip.nat["nat/${az}"].id
    ])
  } : {}

  zonal_nat_gateways_to_create = !local.nat_inject_mode && var.nat_gateway.mode != "regional" ? {
    for az in local.nat_az_set : "nat/${az}" => {
      az                          = az
      allocation_id               = var.nat_gateway.connectivity_type == "private" ? null : local.nat_eip_mode == "existing" ? var.nat_gateway.eip.allocation_ids[az] : aws_eip.nat["nat/${az}"].id
      availability_mode           = "zonal"
      availability_zone_addresses = {}
      connectivity_type           = var.nat_gateway.connectivity_type
      subnet_id                   = local.nat_host_group != null ? try(local.subnet_ids["${local.nat_host_group}/${az}"], null) : null
      vpc_id                      = null
      name                        = local.nat_names[az]
      tags                        = local.nat_resource_tags
    }
  } : {}

  regional_nat_gateways_to_create = !local.nat_inject_mode && var.nat_gateway.mode == "regional" ? {
    "nat/regional" = {
      az                          = null
      allocation_id               = null
      availability_mode           = "regional"
      availability_zone_addresses = local.regional_nat_availability_zone_addresses
      connectivity_type           = "public"
      subnet_id                   = null
      vpc_id                      = local.vpc_id
      name                        = local.regional_nat_name
      tags                        = local.nat_resource_tags
    }
  } : {}

  nat_gateways_to_create = merge(
    local.zonal_nat_gateways_to_create,
    local.regional_nat_gateways_to_create,
  )

  # ─── EIGW ───────────────────────────────────────────────────────────────
  needs_eigw = anytrue([
    for k, v in var.subnets : try(v.routing.egress_only_igw, false)
  ])
  create_eigw = local.needs_eigw && var.vpc.eigw_create
  eigw_id = !local.needs_eigw ? null : (
    local.create_eigw ? aws_egress_only_internet_gateway.main[0].id : coalesce(var.vpc.eigw_id, "eigw-invalid")
  )

  # ─── Route Tables: create-or-inject ────────────────────────────────────
  # Create one route table per group/AZ unless the subnet group injects one
  # shared route_table_id. Associations and outputs consume the unified ID map.
  route_table_map = {
    for key, s in local.subnet_map : key => {
      name             = s.name
      az               = s.az
      name_prefix      = s.name_prefix
      route_table_name = s.route_table_name
      tags             = s.tags
    } if s.manage_route_table
  }

  route_table_id_by_subnet = {
    for key, s in local.subnet_map : key => (
      s.manage_route_table ? aws_route_table.main[key].id : s.route_table_id
    )
  }

  # A caller-owned key represents each injected physical route table. Multiple
  # groups may reference one key; their routing intent is unioned and resources
  # are materialized once for that physical identity.
  injected_route_table_groups_by_key = {
    for name, cfg in var.subnets : cfg.route_table_key => name...
    if !cfg.manage_route_table
  }
  injected_route_table_ids_by_key = {
    for key, groups in local.injected_route_table_groups_by_key :
    key => var.subnets[groups[0]].route_table_id
  }
  managed_route_table_targets = merge([
    for name, cfg in var.subnets : {
      for az in local.azs : "${name}/${az}" => {
        name           = name
        az             = az
        route_table_id = aws_route_table.main["${name}/${az}"].id
        routing        = local.resolved_routing[name]
        routes         = cfg.routes
        has_ipv6       = cfg.ipv6 != null
      }
    } if cfg.manage_route_table
  ]...)
  injected_route_table_targets = {
    for key, groups in local.injected_route_table_groups_by_key : "injected/${key}" => {
      name           = key
      az             = null
      route_table_id = local.injected_route_table_ids_by_key[key]
      routing = {
        internet_gateway          = anytrue([for group in groups : local.resolved_routing[group].internet_gateway])
        nat_gateway               = anytrue([for group in groups : local.resolved_routing[group].nat_gateway])
        egress_only_igw           = anytrue([for group in groups : local.resolved_routing[group].egress_only_igw])
        dns64                     = anytrue([for group in groups : local.resolved_routing[group].dns64])
        s3_gateway_endpoint       = anytrue([for group in groups : local.resolved_routing[group].s3_gateway_endpoint])
        dynamodb_gateway_endpoint = anytrue([for group in groups : local.resolved_routing[group].dynamodb_gateway_endpoint])
        transit_gateway           = distinct(flatten([for group in groups : coalesce(local.resolved_routing[group].transit_gateway, [])]))
        transit_gateway_ipv6      = distinct(flatten([for group in groups : coalesce(local.resolved_routing[group].transit_gateway_ipv6, [])]))
        transit_gateway_attachments = {
          for attachment_key in distinct(flatten([for group in groups : keys(local.resolved_routing[group].transit_gateway_attachments)])) :
          attachment_key => distinct(flatten([for group in groups : lookup(local.resolved_routing[group].transit_gateway_attachments, attachment_key, [])]))
        }
        transit_gateway_attachments_ipv6 = {
          for attachment_key in distinct(flatten([for group in groups : keys(local.resolved_routing[group].transit_gateway_attachments_ipv6)])) :
          attachment_key => distinct(flatten([for group in groups : lookup(local.resolved_routing[group].transit_gateway_attachments_ipv6, attachment_key, [])]))
        }
        core_network      = distinct(flatten([for group in groups : coalesce(local.resolved_routing[group].core_network, [])]))
        core_network_ipv6 = distinct(flatten([for group in groups : coalesce(local.resolved_routing[group].core_network_ipv6, [])]))
      }
      routes   = merge([for group in groups : var.subnets[group].routes]...)
      has_ipv6 = anytrue([for group in groups : var.subnets[group].ipv6 != null])
    }
  }
  route_table_targets = merge(
    local.managed_route_table_targets,
    local.injected_route_table_targets,
  )

  # Normalize every opinionated route to its physical destination and target.
  # Resource addresses remain unchanged; this collection exists only to reject
  # ambiguous tables before AWS sees duplicate or isolation-breaking routes.
  route_intents_by_table = {
    for key, rt in local.route_table_targets : key => concat(
      rt.routing.internet_gateway ? [{ destination = "ipv4:0.0.0.0/0", target = "igw" }] : [],
      rt.routing.internet_gateway && rt.has_ipv6 ? [{ destination = "ipv6:::/0", target = "igw" }] : [],
      rt.routing.nat_gateway ? [{ destination = "ipv4:0.0.0.0/0", target = "nat" }] : [],
      rt.routing.dns64 ? [{ destination = "ipv6:64:ff9b::/96", target = "nat" }] : [],
      rt.routing.egress_only_igw ? [{ destination = "ipv6:::/0", target = "eigw" }] : [],
      [for dest in distinct(coalesce(rt.routing.transit_gateway, [])) : {
        destination = startswith(dest, "pl-") ? "prefix:${dest}" : "ipv4:${dest}"
        target      = "tgw:${coalesce(local.singular_tgw_route_key, "missing")}"
      }],
      [for dest in distinct(coalesce(rt.routing.transit_gateway_ipv6, [])) : {
        destination = startswith(dest, "pl-") ? "prefix:${dest}" : "ipv6:${dest}"
        target      = "tgw:${coalesce(local.singular_tgw_route_key, "missing")}"
      }],
      flatten([
        for attachment_key, destinations in rt.routing.transit_gateway_attachments : [
          for dest in distinct(destinations) : {
            destination = startswith(dest, "pl-") ? "prefix:${dest}" : "ipv4:${dest}"
            target      = "tgw:${attachment_key}"
          }
        ]
      ]),
      flatten([
        for attachment_key, destinations in rt.routing.transit_gateway_attachments_ipv6 : [
          for dest in distinct(destinations) : {
            destination = startswith(dest, "pl-") ? "prefix:${dest}" : "ipv6:${dest}"
            target      = "tgw:${attachment_key}"
          }
        ]
      ]),
      [for dest in distinct(coalesce(rt.routing.core_network, [])) : {
        destination = startswith(dest, "pl-") ? "prefix:${dest}" : "ipv4:${dest}"
        target      = "cwan"
      }],
      [for dest in distinct(coalesce(rt.routing.core_network_ipv6, [])) : {
        destination = startswith(dest, "pl-") ? "prefix:${dest}" : "ipv6:${dest}"
        target      = "cwan"
      }],
      [for route in values(rt.routes) : {
        destination = "${route.destination.type == "ipv4_cidr" ? "ipv4" : route.destination.type == "ipv6_cidr" ? "ipv6" : "prefix"}:${route.destination.value}"
        target      = "${route.target.type}:${route.target.id}"
      }],
    )
  }
  route_destination_conflicts = {
    for key, intents in local.route_intents_by_table : key => [
      for destination in distinct([for intent in intents : intent.destination]) : destination
      if length(distinct([for intent in intents : intent.target if intent.destination == destination])) > 1
      ] if length([
        for destination in distinct([for intent in intents : intent.destination]) : destination
        if length(distinct([for intent in intents : intent.target if intent.destination == destination])) > 1
    ]) > 0
  }
  duplicate_generic_route_keys_by_table = {
    for key, groups in local.injected_route_table_groups_by_key : key => [
      for route_key in distinct(flatten([for group in groups : keys(var.subnets[group].routes)])) : route_key
      if length(flatten([
        for group in groups : [for candidate in keys(var.subnets[group].routes) : candidate if candidate == route_key]
      ])) > 1
      ] if length([
        for route_key in distinct(flatten([for group in groups : keys(var.subnets[group].routes)])) : route_key
        if length(flatten([
          for group in groups : [for candidate in keys(var.subnets[group].routes) : candidate if candidate == route_key]
        ])) > 1
    ]) > 0
  }
  isolated_shared_route_table_conflicts = {
    for key, groups in local.injected_route_table_groups_by_key : key => groups
    if anytrue([for group in groups : var.subnets[group].role == "isolated"]) && anytrue([
      for group in groups :
      local.resolved_routing[group].internet_gateway ||
      local.resolved_routing[group].nat_gateway ||
      local.resolved_routing[group].egress_only_igw ||
      local.resolved_routing[group].dns64 ||
      length(coalesce(local.resolved_routing[group].transit_gateway, [])) > 0 ||
      length(coalesce(local.resolved_routing[group].transit_gateway_ipv6, [])) > 0 ||
      anytrue([for destinations in values(local.resolved_routing[group].transit_gateway_attachments) : length(destinations) > 0]) ||
      anytrue([for destinations in values(local.resolved_routing[group].transit_gateway_attachments_ipv6) : length(destinations) > 0]) ||
      length(coalesce(local.resolved_routing[group].core_network, [])) > 0 ||
      length(coalesce(local.resolved_routing[group].core_network_ipv6, [])) > 0
    ])
  }

  # ─── Core Network ARN resolution ────────────────────────────────────────
  core_network_arn = try([
    for name, cfg in var.subnets : coalesce(
      try(cfg.core_network_options.arn, null),
      "arn:${data.aws_partition.current[0].partition}:networkmanager::${data.aws_caller_identity.current[0].account_id}:core-network/${cfg.core_network_options.id}"
    )
    if cfg.role == "core_network"
  ][0], null)

  # ─── Route Sets ─────────────────────────────────────────────────────────
  # Each route set is keyed by stable route-table identity plus destination.

  # IGW IPv4 routes: route tables whose subnet group requests internet access.
  routes_igw = {
    for key, rt in local.route_table_targets : "${key}/igw" => {
      route_table_id = rt.route_table_id
    } if rt.routing.internet_gateway
  }

  # IGW IPv6 routes: dual-stack public groups also get an IPv6 default route.
  routes_igw_ipv6 = {
    for key, rt in local.route_table_targets : "${key}/igw6" => {
      route_table_id = rt.route_table_id
    } if rt.routing.internet_gateway && rt.has_ipv6
  }

  # NAT routes: resolve single-AZ or per-AZ keys. Regional mode repeats one
  # physical ID across AZ keys, so shared injected route tables remain valid.
  routes_nat = var.nat_gateway.mode != "none" ? {
    for key, rt in local.route_table_targets : "${key}/nat" => {
      route_table_id = rt.route_table_id
      nat_gw_id = (
        var.nat_gateway.mode == "single_az"
        ? local.nat_gateway_ids[var.nat_gateway.az]
        : local.nat_gateway_ids[coalesce(rt.az, local.azs[0])]
      )
    } if rt.routing.nat_gateway
  } : {}

  # NAT64 routes: DNS64 synthesis requires 64:ff9b::/96 to reach a NAT GW.
  routes_nat64 = var.nat_gateway.mode != "none" ? {
    for key, rt in local.route_table_targets : "${key}/nat64" => {
      route_table_id = rt.route_table_id
      nat_gw_id = (
        var.nat_gateway.mode == "single_az"
        ? local.nat_gateway_ids[var.nat_gateway.az]
        : local.nat_gateway_ids[coalesce(rt.az, local.azs[0])]
      )
    } if rt.routing.dns64
  } : {}

  # EIGW routes: subnets with egress_only_igw = true.
  routes_eigw = {
    for key, rt in local.route_table_targets : "${key}/eigw" => {
      route_table_id = rt.route_table_id
    } if rt.routing.egress_only_igw
  }

  routes_custom = merge([
    for key, rt in local.route_table_targets : {
      for route_key, route in rt.routes : "${key}/custom/${route_key}" => {
        route_table_id = rt.route_table_id
        destination    = route.destination
        target         = route.target
      }
    }
  ]...)

  # Destination CIDRs, not list positions, form route keys. Reordering a list
  # therefore produces no resource churn; adding/removing affects one route.
  routes_tgw = local.singular_tgw_route_key != null ? merge([
    for key, rt in local.route_table_targets : {
      for dest in coalesce(rt.routing.transit_gateway, []) :
      "${key}/tgw/${replace(dest, "/", "-")}" => {
        route_table_id = rt.route_table_id
        destination    = dest
        tgw_id         = try(local.transit_gateway_ids_by_attachment[local.singular_tgw_route_key], null)
      }
    } if rt.routing.transit_gateway != null
  ]...) : {}

  routes_tgw_ipv6 = local.singular_tgw_route_key != null ? merge([
    for key, rt in local.route_table_targets : {
      for dest in coalesce(rt.routing.transit_gateway_ipv6, []) :
      "${key}/tgw6/${replace(dest, "/", "-")}" => {
        route_table_id = rt.route_table_id
        destination    = dest
        tgw_id         = try(local.transit_gateway_ids_by_attachment[local.singular_tgw_route_key], null)
      }
    } if rt.routing.transit_gateway_ipv6 != null
  ]...) : {}

  routes_tgw_attachments = merge(flatten([
    for key, rt in local.route_table_targets : [
      for attachment_key, destinations in rt.routing.transit_gateway_attachments : {
        for dest in destinations :
        "${key}/tgw/${attachment_key}/${replace(dest, "/", "-")}" => {
          route_table_id = rt.route_table_id
          destination    = dest
          tgw_id         = try(local.transit_gateway_ids_by_attachment[attachment_key], null)
        }
      }
    ]
  ])...)

  routes_tgw_attachments_ipv6 = merge(flatten([
    for key, rt in local.route_table_targets : [
      for attachment_key, destinations in rt.routing.transit_gateway_attachments_ipv6 : {
        for dest in destinations :
        "${key}/tgw6/${attachment_key}/${replace(dest, "/", "-")}" => {
          route_table_id = rt.route_table_id
          destination    = dest
          tgw_id         = try(local.transit_gateway_ids_by_attachment[attachment_key], null)
        }
      }
    ]
  ])...)

  routes_cwan = local.core_network_arn != null ? merge([
    for key, rt in local.route_table_targets : {
      for dest in coalesce(rt.routing.core_network, []) :
      "${key}/cwan/${replace(dest, "/", "-")}" => {
        route_table_id   = rt.route_table_id
        destination      = dest
        core_network_arn = local.core_network_arn
      }
    } if rt.routing.core_network != null
  ]...) : {}

  routes_cwan_ipv6 = local.core_network_arn != null ? merge([
    for key, rt in local.route_table_targets : {
      for dest in coalesce(rt.routing.core_network_ipv6, []) :
      "${key}/cwan6/${replace(dest, "/", "-")}" => {
        route_table_id   = rt.route_table_id
        destination      = dest
        core_network_arn = local.core_network_arn
      }
    } if rt.routing.core_network_ipv6 != null
  ]...) : {}
}
