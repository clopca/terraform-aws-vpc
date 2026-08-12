# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Subnet Engine (locals.tf)
#
# CIDR Assignment Strategy:
#   1. EXPLICIT cidrs (first-class): user provides one CIDR per AZ — used as-is.
#   2. IPAM: ipam_pool_id + netmask_length — AWS allocates at apply time.
#   3. NETMASK (calculated): deterministic derivation from VPC CIDR.
#
# Deterministic CIDR Calculation (netmask mode):
#   - Subnet groups using `netmask` are sorted ALPHABETICALLY by map key name.
#   - Within each group, AZs are assigned in the order defined in local.azs.
#   - The algorithm: for each group (sorted by name), allocate N contiguous blocks
#     (where N = number of AZs) of size /netmask from the VPC CIDR.
#   - Result: adding/removing a subnet group ONLY affects groups that sort AFTER it.
#   - Result: adding/removing an AZ ONLY affects the last AZ slots within each group.
#   - NEVER positional by insertion order — always alphabetical by name.
#
# State Key Format: "${subnet_group_name}/${az}" for ALL resources.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # ─── AZ Resolution ───────────────────────────────────────────────────────
  # When `names` is provided, use directly. When `count` is used, we rely on
  # the data source (defined in main.tf) to get region AZs.
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

  # ─── Deterministic CIDR Calculation (netmask mode) ──────────────────────
  # Step 1: Build an ordered list of (name, netmask, az_index) tuples sorted by
  #          name (alphabetical) then AZ index. This defines the allocation order.
  #
  # The algorithm uses `cidrsubnet()` with a sequential network number.
  # Each subnet group consumes `az_count` consecutive slots at its netmask size.
  #
  # To handle mixed netmask sizes (e.g. /22 and /24), we allocate in groups
  # sorted by netmask size DESC (larger blocks first to avoid fragmentation),
  # then alphabetically within same size.

  netmask_groups_sorted = sort([
    for name, cfg in local.subnets_with_netmask :
    # Composite sort key: netmask (zero-padded for proper string sort) + name
    # Smaller netmask number = larger block = allocate first
    format("%02d|%s", cfg.ipv4.netmask, name)
  ])

  # Step 2: Build the sequential allocation with a running offset per netmask size.
  # Because cidrsubnet needs a uniform newbits value per call, we group by netmask.
  # Each netmask size gets its own cidrsubnet space from the VPC CIDR.
  #
  # For each unique netmask, calculate:
  #   newbits = subnet_netmask - vpc_prefix_length
  #   max_subnets = 2^newbits
  #
  # Allocation order within a netmask group: alphabetical by name, then by AZ order.

  vpc_prefix_length = tonumber(split("/", local.vpc_cidr)[1])

  # Unique netmask values, sorted (smallest number = largest subnet first)
  unique_netmasks = sort(distinct([
    for name, cfg in local.subnets_with_netmask : cfg.ipv4.netmask
  ]))

  # For each netmask value, which subnet groups use it (sorted alphabetically)
  groups_by_netmask = {
    for nm in local.unique_netmasks : nm => sort([
      for name, cfg in local.subnets_with_netmask : name if cfg.ipv4.netmask == nm
    ])
  }

  # Calculate CIDRs: for each netmask, assign sequential network numbers
  # to groups (alphabetically) × AZs (in local.azs order)
  calculated_cidrs = merge([
    for nm in local.unique_netmasks : {
      for pair in flatten([
        for gi, group_name in local.groups_by_netmask[nm] : [
          for ai, az in local.azs : {
            key     = "${group_name}/${az}"
            netnum  = gi * local.az_count + ai
            newbits = nm - local.vpc_prefix_length
          }
        ]
      ]) : pair.key => cidrsubnet(local.vpc_cidr, pair.newbits, pair.netnum)
    }
  ]...)

  # ─── Flat Subnet Map: "name/az" → config ────────────────────────────────
  # This is the master map that drives aws_subnet.main for_each.
  # Every subnet instance has a unique key "subnet_name/az".

  subnet_map = merge([
    for name, cfg in var.subnets : {
      for ai, az in local.azs : "${name}/${az}" => {
        name        = name
        az          = az
        role        = cfg.role
        name_prefix = coalesce(cfg.name_prefix, name)
        tags        = cfg.tags

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
        routing = cfg.routing

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
}
