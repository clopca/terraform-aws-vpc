# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Typed Contract
#
# Rules: NO type=any, NO count for collections, all for_each keys = "name/az"
# Every resource at the boundary supports create-or-inject pattern.
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# VPC CORE — create-or-inject via vpc.id
# ─────────────────────────────────────────────────────────────────────────────

variable "vpc" {
  description = <<-EOT
    VPC configuration. Set `id` to reference an existing VPC instead of creating one.
    When `id` is set, the module manages subnets/routes within that VPC but does not
    create or modify the VPC resource itself.

    Set `igw_id` to reference an existing Internet Gateway instead of creating one
    (create-or-inject pattern for IGW). [R1-H2]
  EOT
  type = object({
    name             = string
    id               = optional(string) # null = create new VPC; set = inject existing
    igw_id           = optional(string) # null = create IGW if needed; set = use existing [R1-H2]
    instance_tenancy = optional(string, "default")
    dns = optional(object({
      enable_hostnames = optional(bool, true)
      enable_support   = optional(bool, true)
    }), {})
    tags = optional(map(string), {})
  })

  validation {
    condition     = contains(["default", "dedicated", "host"], var.vpc.instance_tenancy)
    error_message = "vpc.instance_tenancy must be one of: default, dedicated, host."
  }

  validation {
    condition     = length(var.vpc.name) > 0
    error_message = "vpc.name must not be empty."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# ADDRESSING (IPv4/IPv6)
# ─────────────────────────────────────────────────────────────────────────────

variable "addressing" {
  description = <<-EOT
    IPv4 and/or IPv6 addressing for the VPC. Supports static CIDR, IPAM, or
    Amazon-assigned IPv6. At least one of ipv4 or ipv6 must be configured.
    For IPAM: provide ipam_pool_id + netmask_length (mutually exclusive with cidr_block).
  EOT
  type = object({
    ipv4 = optional(object({
      cidr_block     = optional(string)
      ipam_pool_id   = optional(string)
      netmask_length = optional(number)
      secondary = optional(list(object({
        cidr_block     = optional(string)
        ipam_pool_id   = optional(string)
        netmask_length = optional(number)
      })), [])
    }))
    ipv6 = optional(object({
      amazon_assigned = optional(bool, false)
      cidr_block      = optional(string)
      ipam_pool_id    = optional(string)
      netmask_length  = optional(number)
    }))
  })

  validation {
    condition     = var.addressing.ipv4 != null || var.addressing.ipv6 != null
    error_message = "At least one of addressing.ipv4 or addressing.ipv6 must be configured."
  }

  validation {
    condition = var.addressing.ipv4 == null ? true : (
      (var.addressing.ipv4.cidr_block != null ? 1 : 0) +
      (var.addressing.ipv4.ipam_pool_id != null ? 1 : 0) <= 1
    )
    error_message = "addressing.ipv4: provide either cidr_block OR ipam_pool_id, not both."
  }

  validation {
    condition = var.addressing.ipv4 == null ? true : (
      var.addressing.ipv4.ipam_pool_id == null || var.addressing.ipv4.netmask_length != null
    )
    error_message = "addressing.ipv4: netmask_length is required when ipam_pool_id is set."
  }

  validation {
    condition = var.addressing.ipv6 == null ? true : (
      (try(var.addressing.ipv6.amazon_assigned, false) ? 1 : 0) +
      (var.addressing.ipv6.cidr_block != null ? 1 : 0) +
      (var.addressing.ipv6.ipam_pool_id != null ? 1 : 0) <= 1
    )
    error_message = "addressing.ipv6: choose at most one of amazon_assigned, cidr_block, or ipam_pool_id."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# AVAILABILITY ZONES
#
# IMPORTANT [R1-H4]: `count` mode takes the first N AZs alphabetically from the
# region. If AWS launches a new AZ that sorts before existing ones, your AZ set
# changes. For PRODUCTION deployments, ALWAYS use explicit `names`. The `count`
# mode is intended for development/prototyping where AZ stability is not critical.
# ─────────────────────────────────────────────────────────────────────────────

variable "availability_zones" {
  description = <<-EOT
    AZ selection. Provide either an explicit list of AZ names or a count
    (takes first N from the region alphabetically). Exactly one is required.

    ⚠️  `count` mode is for DEVELOPMENT ONLY. For production, always use explicit
    `names` to guarantee AZ stability. Because `count` resolves AZ names through an
    AWS data source, preconditions that depend on the resolved AZ set are unknown
    during the initial plan and are deferred by Terraform to apply time.
  EOT
  type = object({
    names = optional(list(string))
    count = optional(number)
  })

  validation {
    condition = (
      (var.availability_zones.names != null ? 1 : 0) +
      (var.availability_zones.count != null ? 1 : 0) == 1
    )
    error_message = "Provide exactly one of availability_zones.names or availability_zones.count."
  }

  validation {
    condition = var.availability_zones.count == null ? true : (
      var.availability_zones.count >= 1 && var.availability_zones.count <= 6
    )
    error_message = "availability_zones.count must be between 1 and 6."
  }

  validation {
    condition = var.availability_zones.names == null ? true : (
      length(var.availability_zones.names) >= 1 && length(var.availability_zones.names) <= 6
    )
    error_message = "availability_zones.names must contain between 1 and 6 AZs."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# SUBNETS — typed with explicit roles and co-located routing
#
# STATE KEY CONTRACT [R1-H1]:
#   Map keys are IMMUTABLE after initial deployment. The state address of every
#   subnet is `aws_subnet.main["<key>/<az>"]`. Renaming a key destroys and
#   recreates all subnets in that group. To rename safely, use Terraform `moved`
#   blocks in your root module:
#     moved { from = aws_subnet.main["old_name/az"] to = aws_subnet.main["new_name/az"] }
#
#   Keys must be stable identifiers (lowercase, alphanumeric + hyphens).
#   If you need a display name different from the state key, use `name_prefix`.
#
# NETMASK STABILITY [R1-C2]:
#   When using `ipv4.netmask`, CIDRs are calculated deterministically:
#   - Every group reserves six AZ slots, so appending AZs does not move CIDRs
#   - Pinned groups use absolute `cidr_index` slots and never move
#   - Unpinned groups pack largest-first, then alphabetically; adding/removing a
#     group affects unpinned groups that sort after it
#   - Overlapping pins across different netmasks fail at plan time
#   - For PRODUCTION, explicit `cidrs` remain the strongest immutability contract
# ─────────────────────────────────────────────────────────────────────────────

variable "subnets" {
  description = <<-EOT
    Map of subnet groups. Each key is a stable logical name (used in state keys
    as "key/az"). Keys are IMMUTABLE post-deploy — renaming requires `moved` blocks.

    The `role` field determines creation behavior:
      - public:          gets IGW route, optional NAT gateway hosting
      - private:         standard private subnet, optional NAT/EIGW routing
      - isolated:        no outbound routing (databases, internal-only)
      - transit_gateway: dedicated small subnets for TGW ENIs
      - core_network:    dedicated small subnets for Cloud WAN attachments

    Multiple subnet groups per role are allowed:
      - public: N groups allowed (e.g. DMZ, edge, GWLB) [R1-C1]
      - transit_gateway: limited to 1 group (AWS API: 1 VPC attachment per TGW per VPC)
        NOTE: if AWS adds multi-attachment support, this constraint will be relaxed
        as a non-breaking change.
      - core_network: limited to 1 group (same AWS API constraint)

    Set `route_table_id` to inject one existing route table for the whole subnet
    group. The module will not create route tables for that group; it associates
    every AZ subnet with the injected table and adds all routes declared in
    `routing` to it. A shared injected table cannot provide per-AZ NAT targets, so
    `nat_gateway.mode = "all_azs"` is rejected when that group requests NAT/NAT64.
  EOT
  type = map(object({
    role = string

    # ── IPv4 Addressing (one of netmask/cidrs/ipam required unless ipv6 native_only) ──
    ipv4 = optional(object({
      netmask        = optional(number)
      cidrs          = optional(list(string))
      ipam_pool_id   = optional(string)
      netmask_length = optional(number)
      # Absolute CIDR group slot for pinning [R1-C2]. Each slot reserves six
      # AZ-sized CIDRs at this netmask. Pinned ranges never move when groups or AZs
      # are added/removed; overlapping pins across netmasks are rejected.
      cidr_index = optional(number)
    }))

    # ── IPv6 Addressing ──
    ipv6 = optional(object({
      auto_assign = optional(bool, false)
      cidrs       = optional(list(string))
      native_only = optional(bool, false)
    }))

    # ── Naming, Tags, and Route Table Injection ──
    name_prefix    = optional(string)
    tags           = optional(map(string), {})
    route_table_id = optional(string) # one existing shared RT for all AZs in this group

    # ── Routing (co-located per subnet group) ──
    # [R1-C3]: transit_gateway and core_network accept lists of destinations
    # to support multiple routes (e.g. 10.0.0.0/8 + 172.16.0.0/12 → TGW).
    # [R2-H3]: internet_gateway defaults to null; auto-resolved as true for
    # role="public", false otherwise. Set explicitly to override.
    routing = optional(object({
      nat_gateway          = optional(bool, false)
      egress_only_igw      = optional(bool, false)
      internet_gateway     = optional(bool)         # null = auto (true for public, false otherwise)
      dns64                = optional(bool, false)  # Also creates 64:ff9b::/96 -> NAT GW; requires NAT
      transit_gateway      = optional(list(string)) # list of CIDRs/prefix-list IDs to route via TGW [R1-C3]
      transit_gateway_ipv6 = optional(list(string)) # list of IPv6 CIDRs/prefix-list IDs [R1-C3]
      core_network         = optional(list(string)) # list of CIDRs/prefix-list IDs to route via CWAN [R1-C3]
      core_network_ipv6    = optional(list(string)) # list of IPv6 CIDRs/prefix-list IDs [R1-C3]
    }), {})

    # ── Public role options ──
    public_options = optional(object({
      map_public_ip = optional(bool, true)
    }))

    # ── Transit Gateway attachment options ──
    transit_gateway_options = optional(object({
      id                              = string
      default_route_table_association = optional(bool, true)
      default_route_table_propagation = optional(bool, true)
      appliance_mode_support          = optional(bool, false)
      dns_support                     = optional(bool, true)
      security_group_referencing      = optional(bool, true) # Requires provider >= 5.69
    }))

    # ── Core Network (Cloud WAN) attachment options ──
    core_network_options = optional(object({
      id                 = string
      arn                = optional(string) # Optional: auto-derived from id if omitted
      appliance_mode     = optional(bool, false)
      require_acceptance = optional(bool, false)
      accept_attachment  = optional(bool, false)
    }))
  }))

  default = {}

  # ── Validations ──

  validation {
    condition = alltrue([
      for k, v in var.subnets :
      v.route_table_id == null ? true : length(trimspace(v.route_table_id)) > 0
    ])
    error_message = "subnets[*].route_table_id must be null or a non-empty route table ID."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets :
      contains(["public", "private", "isolated", "transit_gateway", "core_network"], v.role)
    ])
    error_message = "Each subnet role must be: public, private, isolated, transit_gateway, or core_network."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets : !strcontains(k, "/")
    ])
    error_message = "Subnet map keys must not contain '/' (reserved for state key composition as 'name/az')."
  }

  # R1-C1: REMOVED singleton constraint for public role.
  # Multiple public subnet groups are allowed (DMZ, edge, GWLB, etc.)

  # NOTE [R1-C1]: transit_gateway and core_network remain singleton per AWS API limits
  # (1 VPC attachment per TGW per VPC). If AWS relaxes this, removing the constraint
  # is a non-breaking minor change.
  validation {
    condition     = length([for k, v in var.subnets : k if v.role == "transit_gateway"]) <= 1
    error_message = "At most one subnet group may have role 'transit_gateway' (AWS API: 1 VPC attachment per TGW per VPC)."
  }

  validation {
    condition     = length([for k, v in var.subnets : k if v.role == "core_network"]) <= 1
    error_message = "At most one subnet group may have role 'core_network' (AWS API: 1 Core Network attachment per VPC)."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets :
      v.ipv4 != null || try(v.ipv6.native_only, false)
    ])
    error_message = "Each subnet must define ipv4 addressing or set ipv6.native_only = true."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets :
      v.ipv4 == null ? true : (
        (v.ipv4.netmask != null ? 1 : 0) +
        (v.ipv4.cidrs != null ? 1 : 0) +
        (v.ipv4.ipam_pool_id != null ? 1 : 0) == 1
      )
    ])
    error_message = "Within ipv4, provide exactly one of: netmask, cidrs, or ipam_pool_id."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets :
      v.role != "transit_gateway" || v.transit_gateway_options != null
    ])
    error_message = "Subnets with role 'transit_gateway' must provide transit_gateway_options."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets :
      v.role != "core_network" || v.core_network_options != null
    ])
    error_message = "Subnets with role 'core_network' must provide core_network_options."
  }

  # Extended isolated validation [R1-M1]: prohibit ALL routing including TGW/CWAN
  validation {
    condition = alltrue([
      for k, v in var.subnets :
      v.role == "isolated" ? (
        !try(v.routing.nat_gateway, false) &&
        !try(v.routing.egress_only_igw, false) &&
        try(v.routing.internet_gateway, null) != true &&
        try(v.routing.transit_gateway, null) == null &&
        try(v.routing.core_network, null) == null &&
        try(v.routing.transit_gateway_ipv6, null) == null &&
        try(v.routing.core_network_ipv6, null) == null
      ) : true
    ])
    error_message = "Isolated subnets must not have any routing (nat_gateway, egress_only_igw, internet_gateway, transit_gateway, core_network). Use role 'private' for subnets that need selective routing."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets :
      v.ipv4 == null ? true : (
        v.ipv4.ipam_pool_id == null || v.ipv4.netmask_length != null
      )
    ])
    error_message = "Within ipv4, netmask_length is required when ipam_pool_id is set."
  }

  # Netmask range validation [R2-M1]
  validation {
    condition = alltrue([
      for k, v in var.subnets :
      v.ipv4 == null ? true : (
        v.ipv4.netmask == null ? true : (
          v.ipv4.netmask >= 16 && v.ipv4.netmask <= 28
        )
      )
    ])
    error_message = "ipv4.netmask must be between 16 and 28 for AWS subnets."
  }

  # cidr_index must be a non-negative integer when provided [R1-C2]
  validation {
    condition = alltrue([
      for k, v in var.subnets :
      v.ipv4 == null ? true : (
        v.ipv4.cidr_index == null ? true : (
          v.ipv4.cidr_index >= 0 && floor(v.ipv4.cidr_index) == v.ipv4.cidr_index
        )
      )
    ])
    error_message = "ipv4.cidr_index must be a non-negative integer when provided."
  }

  validation {
    condition = length(distinct([
      for k, v in var.subnets : "${v.ipv4.netmask}/${v.ipv4.cidr_index}"
      if v.ipv4 != null && v.ipv4.netmask != null && v.ipv4.cidr_index != null
      ])) == length([
      for k, v in var.subnets : k
      if v.ipv4 != null && v.ipv4.netmask != null && v.ipv4.cidr_index != null
    ])
    error_message = "Pinned subnet groups using the same ipv4.netmask must have unique ipv4.cidr_index values."
  }

  validation {
    condition = alltrue([
      for key in keys(var.subnets) : can(regex("^[a-z0-9][a-z0-9_-]*$", key))
    ])
    error_message = "Subnet map keys must start with a lowercase letter or digit and contain only lowercase letters, digits, hyphens, and underscores."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.subnets : v.ipv4 == null || v.ipv4.cidrs == null ? [true] : [
        for cidr in v.ipv4.cidrs : can(cidrhost(cidr, 0)) && !strcontains(cidr, ":")
      ]
    ]))
    error_message = "subnets[*].ipv4.cidrs must contain valid IPv4 CIDR blocks."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.subnets : v.ipv6 == null || v.ipv6.cidrs == null ? [true] : [
        for cidr in v.ipv6.cidrs : can(cidrhost(cidr, 0)) && strcontains(cidr, ":")
      ]
    ]))
    error_message = "subnets[*].ipv6.cidrs must contain valid IPv6 CIDR blocks."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets : !try(v.ipv6.native_only, false) || try(v.ipv6.cidrs, null) != null
    ])
    error_message = "IPv6-native subnet groups must provide one explicit ipv6.cidrs entry per AZ."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets :
      (v.role == "public") == (v.public_options != null) || v.public_options == null
    ])
    error_message = "public_options may be set only on subnet groups with role = 'public'."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets : v.role == "transit_gateway" || v.transit_gateway_options == null
    ])
    error_message = "transit_gateway_options may be set only on subnet groups with role = 'transit_gateway'."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets : v.role == "core_network" || v.core_network_options == null
    ])
    error_message = "core_network_options may be set only on subnet groups with role = 'core_network'."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.subnets : [
        for destination in concat(
          coalesce(try(v.routing.transit_gateway, null), []),
          coalesce(try(v.routing.core_network, null), [])
        ) : (can(cidrhost(destination, 0)) && !strcontains(destination, ":")) || can(regex("^pl-[0-9a-f]+$", destination))
      ]
    ]))
    error_message = "IPv4 TGW/Core Network route destinations must be valid CIDRs or managed prefix list IDs (pl-*)."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.subnets : [
        for destination in concat(
          coalesce(try(v.routing.transit_gateway_ipv6, null), []),
          coalesce(try(v.routing.core_network_ipv6, null), [])
        ) : (can(cidrhost(destination, 0)) && strcontains(destination, ":")) || can(regex("^pl-[0-9a-f]+$", destination))
      ]
    ]))
    error_message = "IPv6 TGW/Core Network route destinations must be valid IPv6 CIDRs or managed prefix list IDs (pl-*)."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# NAT GATEWAY — top-level, VPC-wide concern with create-or-inject EIP
#
# [R1-H2]: nat_gateway.existing_ids allows injecting existing NAT Gateways
# instead of creating new ones (full create-or-inject pattern).
# ─────────────────────────────────────────────────────────────────────────────

variable "nat_gateway" {
  description = <<-EOT
    NAT Gateway configuration. Controls how many NAT GWs are created and how
    their Elastic IPs are sourced (create new, use BYOIP pool, or inject existing).
    The `az` field is REQUIRED when mode = "single_az" to avoid positional fragility.

    Set `existing_ids` to inject existing NAT Gateways (create-or-inject pattern).
    When set, the module uses the referenced NAT GWs instead of creating new ones.

    `connectivity_type` controls whether the NAT is public (internet-facing, needs EIP)
    or private (inter-VPC, no EIP). Default: "public".

    `subnet_group` explicitly selects the subnet group that hosts created NAT
    Gateways. It must reference a public group for public NAT or a private group
    for private NAT. Default null preserves convenience behavior by selecting the
    first compatible group alphabetically; set it explicitly in production so
    adding another group cannot relocate the NAT Gateway.
  EOT
  type = object({
    mode              = optional(string, "none")
    az                = optional(string)
    connectivity_type = optional(string, "public") # "public" | "private"
    subnet_group      = optional(string)           # explicit NAT host group; null = first compatible group
    existing_ids      = optional(map(string))      # az → nat_gateway_id, for inject mode [R1-H2]
    eip = optional(object({
      mode             = optional(string, "create")
      public_ipv4_pool = optional(string)
      allocation_ids   = optional(map(string)) # R2-H2: default null instead of {}
    }), { mode = "create" })
  })
  default = { mode = "none" }

  validation {
    condition     = contains(["none", "single_az", "all_azs"], var.nat_gateway.mode)
    error_message = "nat_gateway.mode must be: none, single_az, or all_azs."
  }

  validation {
    condition = var.nat_gateway.mode != "single_az" || (
      var.nat_gateway.az != null && length(var.nat_gateway.az) > 0
    )
    error_message = "nat_gateway.az is required when mode = 'single_az'."
  }

  # R2-H2: allocation_ids is now nullable (default null); validate != null for existing mode
  validation {
    condition = try(var.nat_gateway.eip.mode, "create") == "create" ? true : (
      var.nat_gateway.eip.mode == "byoip_pool" ? var.nat_gateway.eip.public_ipv4_pool != null :
      var.nat_gateway.eip.mode == "existing" ? (
        var.nat_gateway.eip.allocation_ids != null && length(var.nat_gateway.eip.allocation_ids) > 0
      ) : false
    )
    error_message = "eip.mode='byoip_pool' requires public_ipv4_pool; eip.mode='existing' requires allocation_ids (non-null, non-empty)."
  }

  validation {
    condition     = try(contains(["create", "byoip_pool", "existing"], var.nat_gateway.eip.mode), true)
    error_message = "nat_gateway.eip.mode must be: create, byoip_pool, or existing."
  }

  # Existing NAT GWs: only valid when mode != "none"
  validation {
    condition = var.nat_gateway.existing_ids == null ? true : (
      var.nat_gateway.mode != "none"
    )
    error_message = "nat_gateway.existing_ids is only valid when mode is 'single_az' or 'all_azs'."
  }

  validation {
    condition     = contains(["public", "private"], var.nat_gateway.connectivity_type)
    error_message = "nat_gateway.connectivity_type must be 'public' or 'private'."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC FLOW LOGS — native resources, create-or-inject destinations and roles
# ─────────────────────────────────────────────────────────────────────────────

variable "flow_logs" {
  description = <<-EOT
    VPC Flow Logs keyed by a stable logical name. Map keys are Terraform state
    identity and must not be renamed without a moved block.

    destination_type accepts cloudwatch, s3, or kinesis (Kinesis Data Firehose).
    CloudWatch supports create-or-inject for both the log group and the VPC Flow
    Logs IAM role. `cloudwatch_options.name` is the fixed physical log-group name;
    set it to the exact imported v4 name during migration. `role_name_prefix` is
    passed through exactly (maximum 38 characters) so a moved v4 IAM role keeps its
    original prefix and is not replaced. S3 buckets and Firehose delivery streams
    are external resources: destination_arn is required so their lifecycle, KMS,
    retention, and ownership policies remain outside this VPC module.

    Migration note: `cloudwatch_options.name` preserves the physical name only when
    the v4 log group is removed from its old state address and imported at the v5
    address. A moved block from v4 `name_prefix` to v5 `name` is replacement-prone.
  EOT
  type = map(object({
    enabled                        = optional(bool, true)
    destination_type               = optional(string, "cloudwatch")
    destination_arn                = optional(string)
    iam_role_arn                   = optional(string)
    deliver_cross_account_role_arn = optional(string)
    traffic_type                   = optional(string, "ALL")
    log_format                     = optional(string)
    max_aggregation_interval       = optional(number, 600)
    role_name_prefix               = optional(string)
    role_permissions_boundary      = optional(string)
    cloudwatch_options = optional(object({
      name              = optional(string)
      retention_in_days = optional(number, 30)
      kms_key_id        = optional(string)
    }), {})
    s3_options = optional(object({
      file_format                = optional(string, "plain-text")
      hive_compatible_partitions = optional(bool, false)
      per_hour_partition         = optional(bool, false)
    }), {})
    tags = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, cfg in var.flow_logs : contains(["cloudwatch", "s3", "kinesis"], cfg.destination_type)
    ])
    error_message = "flow_logs[*].destination_type must be cloudwatch, s3, or kinesis."
  }

  validation {
    condition = alltrue([
      for name, cfg in var.flow_logs : contains(["ALL", "ACCEPT", "REJECT"], cfg.traffic_type)
    ])
    error_message = "flow_logs[*].traffic_type must be ALL, ACCEPT, or REJECT."
  }

  validation {
    condition = alltrue([
      for name, cfg in var.flow_logs : contains([60, 600], cfg.max_aggregation_interval)
    ])
    error_message = "flow_logs[*].max_aggregation_interval must be 60 or 600 seconds."
  }

  validation {
    condition = alltrue([
      for name, cfg in var.flow_logs : can(regex("^[a-z0-9][a-z0-9-]*$", name)) && !strcontains(name, "/")
    ])
    error_message = "Flow log map keys must use lowercase alphanumeric characters and hyphens, and must not contain '/'."
  }

  validation {
    condition = alltrue([
      for name, cfg in var.flow_logs : contains(["plain-text", "parquet"], cfg.s3_options.file_format)
    ])
    error_message = "flow_logs[*].s3_options.file_format must be plain-text or parquet."
  }

  validation {
    condition = alltrue([
      for name, cfg in var.flow_logs : cfg.destination_type == "cloudwatch" || cfg.iam_role_arn == null
    ])
    error_message = "flow_logs[*].iam_role_arn is only valid for destination_type = cloudwatch."
  }

  validation {
    condition = alltrue([
      for name, cfg in var.flow_logs : cfg.destination_arn == null || length(trimspace(cfg.destination_arn)) > 0
    ])
    error_message = "flow_logs[*].destination_arn must be null or a non-empty ARN."
  }

  validation {
    condition = alltrue([
      for name, cfg in var.flow_logs : cfg.cloudwatch_options.name == null || length(trimspace(cfg.cloudwatch_options.name)) > 0
    ])
    error_message = "flow_logs[*].cloudwatch_options.name must be null or a non-empty fixed log-group name."
  }

  validation {
    condition = alltrue([
      for name, cfg in var.flow_logs : cfg.role_name_prefix == null || (
        length(trimspace(cfg.role_name_prefix)) > 0 && length(cfg.role_name_prefix) <= 38
      )
    ])
    error_message = "flow_logs[*].role_name_prefix must be null or a non-empty IAM role name prefix of at most 38 characters."
  }

  validation {
    condition = alltrue([
      for name, cfg in var.flow_logs : contains(["s3", "kinesis"], cfg.destination_type) ? cfg.destination_arn != null : true
    ])
    error_message = "flow_logs[*].destination_arn is required for S3 and Kinesis Data Firehose destinations; those resources are externally managed."
  }

  validation {
    condition = alltrue([
      for name, cfg in var.flow_logs : contains([
        1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731,
        1096, 1827, 2192, 2557, 2922, 3288, 3653
      ], cfg.cloudwatch_options.retention_in_days)
    ])
    error_message = "flow_logs[*].cloudwatch_options.retention_in_days must be a retention period supported by CloudWatch Logs."
  }

  validation {
    condition = alltrue([
      for name, cfg in var.flow_logs : cfg.deliver_cross_account_role_arn == null || length(trimspace(cfg.deliver_cross_account_role_arn)) > 0
    ])
    error_message = "flow_logs[*].deliver_cross_account_role_arn must be null or a non-empty ARN."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC LATTICE — typed Service Network association
# ─────────────────────────────────────────────────────────────────────────────

variable "vpc_lattice" {
  description = "VPC Lattice Service Network association. Null disables the association."
  type = object({
    service_network_identifier = string
    security_group_ids         = optional(set(string), [])
    private_dns_enabled        = optional(bool, false)
    tags                       = optional(map(string), {})
  })
  default = null

  validation {
    condition = var.vpc_lattice == null ? true : (
      length(trimspace(var.vpc_lattice.service_network_identifier)) > 0 &&
      alltrue([for id in var.vpc_lattice.security_group_ids : length(trimspace(id)) > 0]) &&
      length(var.vpc_lattice.security_group_ids) <= 5
    )
    error_message = "vpc_lattice requires a non-empty service_network_identifier and at most five non-empty security_group_ids."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# GLOBAL TAGS
# ─────────────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}
