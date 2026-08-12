# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Typed Contract
#
# Rules: NO type=any, NO count for collections, all for_each keys = "name/az"
# Every resource at the boundary supports create-or-inject pattern.
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC CORE — create-or-inject via vpc.id
# ─────────────────────────────────────────────────────────────────────────────

variable "vpc" {
  description = <<-EOT
    VPC configuration. Set `id` to reference an existing VPC instead of creating one.
    When `id` is set, the module manages subnets/routes within that VPC but does not
    create or modify the VPC resource itself.
  EOT
  type = object({
    name             = string
    id               = optional(string) # null = create new VPC; set = inject existing
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
# ─────────────────────────────────────────────────────────────────────────────

variable "availability_zones" {
  description = <<-EOT
    AZ selection. Provide either an explicit list of AZ names or a count
    (takes first N from the region alphabetically). Exactly one is required.
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
# ─────────────────────────────────────────────────────────────────────────────

variable "subnets" {
  description = <<-EOT
    Map of subnet groups. Each key is a stable logical name (used in state keys
    as "key/az"). The `role` field determines creation behavior:
      - public:          gets IGW route, optional NAT gateway hosting
      - private:         standard private subnet, optional NAT/EIGW routing
      - isolated:        no outbound routing (databases, internal-only)
      - transit_gateway: dedicated small subnets for TGW ENIs
      - core_network:    dedicated small subnets for Cloud WAN attachments
  EOT
  type = map(object({
    role = string

    # ── IPv4 Addressing (one of netmask/cidrs/ipam required unless ipv6 native_only) ──
    ipv4 = optional(object({
      netmask        = optional(number)
      cidrs          = optional(list(string))
      ipam_pool_id   = optional(string)
      netmask_length = optional(number)
    }))

    # ── IPv6 Addressing ──
    ipv6 = optional(object({
      auto_assign = optional(bool, false)
      cidrs       = optional(list(string))
      native_only = optional(bool, false)
    }))

    # ── Naming & Tags ──
    name_prefix = optional(string)
    tags        = optional(map(string), {})

    # ── Routing (co-located per subnet group) ──
    routing = optional(object({
      nat_gateway          = optional(bool, false)
      egress_only_igw      = optional(bool, false)
      internet_gateway     = optional(bool)
      transit_gateway      = optional(string)
      transit_gateway_ipv6 = optional(string)
      core_network         = optional(string)
      core_network_ipv6    = optional(string)
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
      security_group_referencing      = optional(bool, true)
    }))

    # ── Core Network (Cloud WAN) attachment options ──
    core_network_options = optional(object({
      id                 = string
      arn                = string
      appliance_mode     = optional(bool, false)
      require_acceptance = optional(bool, false)
      accept_attachment  = optional(bool, true)
    }))
  }))

  default = {}

  # ── Validations ──

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

  validation {
    condition     = length([for k, v in var.subnets : k if v.role == "public"]) <= 1
    error_message = "At most one subnet group may have role 'public'."
  }

  validation {
    condition     = length([for k, v in var.subnets : k if v.role == "transit_gateway"]) <= 1
    error_message = "At most one subnet group may have role 'transit_gateway'."
  }

  validation {
    condition     = length([for k, v in var.subnets : k if v.role == "core_network"]) <= 1
    error_message = "At most one subnet group may have role 'core_network'."
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

  validation {
    condition = alltrue([
      for k, v in var.subnets :
      v.role == "isolated" ? (
        !try(v.routing.nat_gateway, false) &&
        !try(v.routing.egress_only_igw, false) &&
        try(v.routing.internet_gateway, null) != true
      ) : true
    ])
    error_message = "Isolated subnets must not have outbound routing (nat_gateway, egress_only_igw, internet_gateway)."
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
}

# ─────────────────────────────────────────────────────────────────────────────
# NAT GATEWAY — top-level, VPC-wide concern with create-or-inject EIP
# ─────────────────────────────────────────────────────────────────────────────

variable "nat_gateway" {
  description = <<-EOT
    NAT Gateway configuration. Controls how many NAT GWs are created and how
    their Elastic IPs are sourced (create new, use BYOIP pool, or inject existing).
    The `az` field is REQUIRED when mode = "single_az" to avoid positional fragility.
  EOT
  type = object({
    mode = optional(string, "none")
    az   = optional(string)
    eip = optional(object({
      mode             = optional(string, "create")
      public_ipv4_pool = optional(string)
      allocation_ids   = optional(map(string), {})
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

  validation {
    condition = try(var.nat_gateway.eip.mode, "create") == "create" ? true : (
      var.nat_gateway.eip.mode == "byoip_pool" ? var.nat_gateway.eip.public_ipv4_pool != null :
      var.nat_gateway.eip.mode == "existing" ? length(var.nat_gateway.eip.allocation_ids) > 0 :
      false
    )
    error_message = "eip.mode='byoip_pool' requires public_ipv4_pool; eip.mode='existing' requires allocation_ids."
  }

  validation {
    condition     = try(contains(["create", "byoip_pool", "existing"], var.nat_gateway.eip.mode), true)
    error_message = "nat_gateway.eip.mode must be: create, byoip_pool, or existing."
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
