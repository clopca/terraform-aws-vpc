# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Subnet Engine (locals.tf)
#
# CIDR Assignment Strategy:
#   1. EXPLICIT cidrs (first-class): user provides one CIDR per AZ — used as-is.
#   2. IPAM: ipam_pool_id + netmask_length — AWS allocates at apply time.
#   3. NETMASK (calculated): deterministic derivation from VPC CIDR.
#
# ═══════════════════════════════════════════════════════════════════════════════
# DETERMINISTIC CIDR CALCULATION — STABILITY PROOF [R1-C2]
# ═══════════════════════════════════════════════════════════════════════════════
#
# Algorithm (two-tier with pinning):
#
#   TIER 1 — PINNED GROUPS (cidr_index set):
#     Groups with explicit `cidr_index` are allocated FIRST, using their index
#     as the network number within their netmask's address space.
#     These are immune to any addition/removal of other groups.
#
#   TIER 2 — UNPINNED GROUPS (cidr_index = null):
#     Remaining groups are allocated after all pinned slots, sorted by:
#       1. Netmask size DESCENDING (larger blocks = smaller netmask number first)
#       2. Alphabetically by key name within same netmask
#     Sequential network numbers start AFTER the highest pinned index.
#
# STABILITY GUARANTEES:
#
#   Scenario 1: Add a new group "beta" (unpinned) to existing ["alpha", "gamma"]
#     Before: alpha=netnum 0, gamma=netnum 1
#     After:  alpha=netnum 0, beta=netnum 1, gamma=netnum 2
#     ⚠️ gamma's CIDR SHIFTS. This is the documented trade-off of netmask mode.
#
#   Scenario 2: Same setup but alpha has cidr_index=0, gamma has cidr_index=5
#     Before: alpha=netnum 0 (pinned), gamma=netnum 5 (pinned)
#     After:  alpha=netnum 0 (pinned), gamma=netnum 5 (pinned), beta=netnum 6 (unpinned, after max pin)
#     ✅ Neither alpha nor gamma shifts. Beta gets the next available slot.
#
#   Scenario 3: Remove "beta" from ["alpha", "beta", "gamma"] (all unpinned)
#     Before: alpha=netnum 0, beta=netnum 1, gamma=netnum 2
#     After:  alpha=netnum 0, gamma=netnum 1
#     ⚠️ gamma shifts. Use pinning or explicit cidrs for immutable allocations.
#
#   Scenario 4: Add AZ to existing 2-AZ deployment
#     Only the NEW AZ slots are appended within each group. Existing AZ CIDRs
#     are stable (network number = group_offset * az_count + az_index).
#     ⚠️ If az_count changes, groups that used to fit may now overlap with the
#     next group's space. Use explicit cidrs for production multi-AZ changes.
#
# PRODUCTION RECOMMENDATION:
#   Use explicit `cidrs` for any subnet group that must never shift.
#   Use `cidr_index` for development/staging where you want auto-calculation
#   with guaranteed slot reservation.
#   Use bare `netmask` only for throwaway environments where destroy is acceptable.
#
# State Key Format: "${subnet_group_name}/${az}" for ALL resources.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # ─── AZ Resolution ───────────────────────────────────────────────────────
  # When `names` is provided, use directly. When `count` is used, we rely on
  # the data source (defined in main.tf) to get region AZs.
  # [R1-H4]: count mode depends on data source ordering — development only.
  azs      = coalesce(var.availability_zones.names, data.aws_availability_zones.current[0].names)
  az_count = length(local.azs)

  # ─── VPC Identity ───────────────────────────────────────────────────────
  create_vpc = var.vpc.id == null
  vpc_id     = local.create_vpc ? aws_vpc.main[0].id : var.vpc.id

  # Primary CIDR — needed for netmask calculation
  vpc_cidr = local.create_vpc ? aws_vpc.main[0].cidr_block : data.aws_vpc.existing[0].cidr_block

  # ─── Subnet Group Classification ────────────────────────────────────────
  # Sorted keys for deterministic processing
  subnet_names_sorted = sort(keys(var.subnets))

  # Groups by addressing mode
  subnets_with_netmask = {
    for k, v in var.subnets : k => v if v.ipv4 != null && v.ipv4.netmask != null
  }
  subnets_with_cidrs = {
    for k, v in var.subnets : k => v if v.ipv4 != null && v.ipv4.cidrs != null
  }
  subnets_with_ipam = {
    for k, v in var.subnets : k => v if v.ipv4 != null && v.ipv4.ipam_pool_id != null
  }

  # ─── Deterministic CIDR Calculation with Pinning [R1-C2] ───────────────
  #
  # Two-tier allocation:
  #   1. Pinned groups (cidr_index != null) — reserved slots, immune to changes
  #   2. Unpinned groups — sequential after highest pinned slot, alphabetical

  vpc_prefix_length = tonumber(split("/", local.vpc_cidr)[1])

  # Unique netmask values, sorted (smallest number = largest subnet first)
  unique_netmasks = sort(distinct([
    for name, cfg in local.subnets_with_netmask : cfg.ipv4.netmask
  ]))

  # ── Per-netmask: separate pinned from unpinned groups ──

  # Pinned groups per netmask (sorted by cidr_index)
  pinned_by_netmask = {
    for nm in local.unique_netmasks : nm => sort([
      for name, cfg in local.subnets_with_netmask :
      format("%06d|%s", cfg.ipv4.cidr_index, name)
      if cfg.ipv4.netmask == nm && cfg.ipv4.cidr_index != null
    ])
  }

  # Unpinned groups per netmask (sorted alphabetically)
  unpinned_by_netmask = {
    for nm in local.unique_netmasks : nm => sort([
      for name, cfg in local.subnets_with_netmask : name
      if cfg.ipv4.netmask == nm && cfg.ipv4.cidr_index == null
    ])
  }

  # Highest pinned cidr_index per netmask (to start unpinned after it)
  max_pinned_index_by_netmask = {
    for nm in local.unique_netmasks : nm => (
      length([
        for name, cfg in local.subnets_with_netmask :
        cfg.ipv4.cidr_index
        if cfg.ipv4.netmask == nm && cfg.ipv4.cidr_index != null
      ]) > 0 ?
      max([
        for name, cfg in local.subnets_with_netmask :
        cfg.ipv4.cidr_index
        if cfg.ipv4.netmask == nm && cfg.ipv4.cidr_index != null
      ]...) : -1
    )
  }

  # ── Calculate CIDRs ──
  # Pinned groups: use their cidr_index directly as the group offset
  # Unpinned groups: start after (max_pinned_index + 1), sequential

  calculated_cidrs = merge(
    # Pinned CIDRs
    merge([
      for nm in local.unique_netmasks : {
        for pair in flatten([
          for entry in local.pinned_by_netmask[nm] : [
            for ai, az in local.azs : {
              key     = "${split("|", entry)[1]}/${az}"
              netnum  = tonumber(split("|", entry)[0]) * local.az_count + ai
              newbits = nm - local.vpc_prefix_length
            }
          ]
        ]) : pair.key => cidrsubnet(local.vpc_cidr, pair.newbits, pair.netnum)
      }
    ]...),
    # Unpinned CIDRs
    merge([
      for nm in local.unique_netmasks : {
        for pair in flatten([
          for gi, group_name in local.unpinned_by_netmask[nm] : [
            for ai, az in local.azs : {
              key     = "${group_name}/${az}"
              netnum  = (local.max_pinned_index_by_netmask[nm] + 1 + gi) * local.az_count + ai
              newbits = nm - local.vpc_prefix_length
            }
          ]
        ]) : pair.key => cidrsubnet(local.vpc_cidr, pair.newbits, pair.netnum)
      }
    ]...)
  )

  # ─── IGW: create-or-inject [R1-H2] ─────────────────────────────────────
  # Determine if any subnet needs an IGW
  needs_igw = anytrue([
    for k, v in var.subnets :
    v.role == "public" || try(v.routing.internet_gateway, false) == true
  ])
  create_igw = local.needs_igw && var.vpc.igw_id == null
  igw_id     = local.create_igw ? try(aws_internet_gateway.main[0].id, null) : var.vpc.igw_id

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
      dns64                = try(cfg.routing.dns64, false)
      transit_gateway      = try(cfg.routing.transit_gateway, null)
      transit_gateway_ipv6 = try(cfg.routing.transit_gateway_ipv6, null)
      core_network         = try(cfg.routing.core_network, null)
      core_network_ipv6    = try(cfg.routing.core_network_ipv6, null)
    }
  }

  # ─── Flat Subnet Map: "name/az" → config ────────────────────────────────
  # This is the master map that drives aws_subnet.main for_each.
  # Every subnet instance has a unique key "subnet_name/az".

  subnet_map = merge([
    for name, cfg in var.subnets : {
      for ai, az in local.azs : "${name}/${az}" => {
        name           = name
        az             = az
        role           = cfg.role
        name_prefix    = coalesce(cfg.name_prefix, name)
        tags           = cfg.tags
        route_table_id = cfg.route_table_id

        # CIDR resolution: explicit > calculated > IPAM (null, resolved at apply)
        cidr_block = (
          cfg.ipv4 != null && cfg.ipv4.cidrs != null ? cfg.ipv4.cidrs[ai] :
          cfg.ipv4 != null && cfg.ipv4.netmask != null ? local.calculated_cidrs["${name}/${az}"] :
          null # IPAM or ipv6-only
        )

        # IPAM fields (null when not using IPAM for this subnet)
        ipam_pool_id   = try(cfg.ipv4.ipam_pool_id, null)
        netmask_length = try(cfg.ipv4.netmask_length, null)

        # IPv6
        ipv6_cidr   = try(cfg.ipv6.cidrs[ai], null)
        ipv6_native = try(cfg.ipv6.native_only, false)
        assign_ipv6 = try(cfg.ipv6.auto_assign, false)

        # Routing config (carried through for phases 2+)
        routing = local.resolved_routing[name]

        # Role-specific
        map_public_ip           = cfg.role == "public" ? try(cfg.public_options.map_public_ip, true) : false
        transit_gateway_options = cfg.role == "transit_gateway" ? cfg.transit_gateway_options : null
        core_network_options    = cfg.role == "core_network" ? cfg.core_network_options : null
      }
    }
  ]...)

  # ─── Secondary CIDRs ────────────────────────────────────────────────────
  secondary_cidrs = var.addressing.ipv4 != null ? {
    for idx, sec in var.addressing.ipv4.secondary : tostring(idx) => sec
  } : {}

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 2 — NAT GATEWAYS, EIGW, ROUTING
  # ═══════════════════════════════════════════════════════════════════════════

  # ─── NAT Gateway — AZ resolution ────────────────────────────────────────
  # Determine which AZs get a NAT gateway based on mode.
  nat_az_set = (
    var.nat_gateway.mode == "none" ? toset([]) :
    var.nat_gateway.mode == "single_az" ? toset([var.nat_gateway.az]) :
    toset(local.azs) # all_azs
  )

  # Are we injecting existing NAT GWs?
  nat_inject_mode = var.nat_gateway.existing_ids != null

  # ─── NAT Gateway ID map (unified: created or injected) ──────────────────
  # Shape: map(az, nat_gw_id) — used by routing locals to wire routes.
  nat_gateway_ids = (
    local.nat_inject_mode ? var.nat_gateway.existing_ids : {
      for az in local.nat_az_set : az => aws_nat_gateway.main["nat/${az}"].id
    }
  )

  # ─── NAT Gateway subnet placement ──────────────────────────────────────
  # Explicit subnet_group is the production-safe contract. The null fallback is
  # retained for convenience and documented as the first compatible group sorted
  # alphabetically; adding a group can therefore relocate a created NAT Gateway.
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
  nat_host_group = (
    var.nat_gateway.subnet_group != null
    ? var.nat_gateway.subnet_group
    : local.nat_default_host_group
  )

  # ─── EIPs to create ─────────────────────────────────────────────────────
  # Only when: creating NAT GWs (not inject), public connectivity, eip.mode != "existing"
  nat_eips_to_create = (
    !local.nat_inject_mode &&
    var.nat_gateway.connectivity_type == "public" &&
    try(var.nat_gateway.eip.mode, "create") != "existing"
    ) ? {
    for az in local.nat_az_set : "nat/${az}" => { az = az }
  } : {}

  # ─── NAT Gateways to create ─────────────────────────────────────────────
  # Not created when existing_ids are injected.
  nat_gateways_to_create = !local.nat_inject_mode ? {
    for az in local.nat_az_set : "nat/${az}" => {
      az                = az
      connectivity_type = var.nat_gateway.connectivity_type
      subnet_id         = local.nat_host_group != null ? try(aws_subnet.main["${local.nat_host_group}/${az}"].id, null) : null
      allocation_id = (
        var.nat_gateway.connectivity_type == "private" ? null :
        try(var.nat_gateway.eip.mode, "create") == "existing" ?
        var.nat_gateway.eip.allocation_ids[az] :
        aws_eip.nat["nat/${az}"].id
      )
    }
  } : {}

  # ─── EIGW ───────────────────────────────────────────────────────────────
  needs_eigw = anytrue([
    for k, v in var.subnets : try(v.routing.egress_only_igw, false)
  ])
  create_eigw = local.needs_eigw
  eigw_id     = local.create_eigw ? aws_egress_only_internet_gateway.main[0].id : null

  # ─── Route Tables: create-or-inject ────────────────────────────────────
  # Create one route table per group/AZ unless the subnet group injects one
  # shared route_table_id. Associations and outputs consume the unified ID map.
  route_table_map = {
    for key, s in local.subnet_map : key => {
      name        = s.name
      az          = s.az
      name_prefix = s.name_prefix
      tags        = s.tags
    } if s.route_table_id == null
  }

  route_table_id_by_subnet = {
    for key, s in local.subnet_map : key => (
      s.route_table_id != null ? s.route_table_id : aws_route_table.main[key].id
    )
  }

  # Route declarations are materialized once per created RT, or once per group
  # for an injected shared RT. This avoids duplicate routes to the same injected
  # table when a subnet group spans multiple AZs.
  route_table_targets = merge([
    for name, cfg in var.subnets : cfg.route_table_id == null ? {
      for az in local.azs : "${name}/${az}" => {
        name           = name
        az             = az
        route_table_id = aws_route_table.main["${name}/${az}"].id
        routing        = local.resolved_routing[name]
        has_ipv6       = cfg.ipv6 != null
      }
      } : {
      "${name}/injected" = {
        name           = name
        az             = null
        route_table_id = cfg.route_table_id
        routing        = local.resolved_routing[name]
        has_ipv6       = cfg.ipv6 != null
      }
    }
  ]...)

  # ─── TGW ID resolution (from subnet group with role = transit_gateway) ──
  tgw_id = try([
    for name, cfg in var.subnets : cfg.transit_gateway_options.id
    if cfg.role == "transit_gateway"
  ][0], null)

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

  # NAT routes: resolve single-AZ or per-AZ targets. Injected shared route
  # tables are limited by precondition to single_az mode.
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

  # Destination CIDRs, not list positions, form route keys. Reordering a list
  # therefore produces no resource churn; adding/removing affects one route.
  routes_tgw = local.tgw_id != null ? merge([
    for key, rt in local.route_table_targets : {
      for dest in coalesce(rt.routing.transit_gateway, []) :
      "${key}/tgw/${replace(dest, "/", "-")}" => {
        route_table_id = rt.route_table_id
        destination    = dest
        tgw_id         = local.tgw_id
      }
    } if rt.routing.transit_gateway != null
  ]...) : {}

  routes_tgw_ipv6 = local.tgw_id != null ? merge([
    for key, rt in local.route_table_targets : {
      for dest in coalesce(rt.routing.transit_gateway_ipv6, []) :
      "${key}/tgw6/${replace(dest, "/", "-")}" => {
        route_table_id = rt.route_table_id
        destination    = dest
        tgw_id         = local.tgw_id
      }
    } if rt.routing.transit_gateway_ipv6 != null
  ]...) : {}

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
