# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Typed Contract Prototype
# This is a STANDALONE validation prototype. It does NOT provision resources.
# Purpose: validate the schema ergonomics and pass `terraform validate`.
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
# VPC CORE
# ─────────────────────────────────────────────────────────────────────────────

variable "vpc" {
  description = <<-EOT
    VPC configuration. Set `id` to reference an existing VPC instead of creating one.
    When `id` is set, the module manages subnets/routes within that VPC but does not
    create or modify the VPC resource itself.
  EOT
  type = object({
    name             = string
    id               = optional(string) # null = create new VPC
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
      cidr_block     = optional(string) # e.g. "10.0.0.0/16"
      ipam_pool_id   = optional(string) # mutually exclusive with cidr_block
      netmask_length = optional(number) # required with ipam_pool_id
      secondary = optional(list(object({
        cidr_block     = optional(string)
        ipam_pool_id   = optional(string)
        netmask_length = optional(number)
      })), [])
    }))
    ipv6 = optional(object({
      amazon_assigned = optional(bool, false) # /56 auto-assigned by AWS
      cidr_block      = optional(string)      # BYOIPv6
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
    condition = var.addressing.ipv6 == null ? true : (
      (try(var.addressing.ipv6.amazon_assigned, false) ? 1 : 0) +
      (var.addressing.ipv6.cidr_block != null ? 1 : 0) +
      (var.addressing.ipv6.ipam_pool_id != null ? 1 : 0) <= 1
    )
    error_message = "addressing.ipv6: choose exactly one of amazon_assigned, cidr_block, or ipam_pool_id."
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
    names = optional(list(string)) # ["us-east-1a", "us-east-1b", "us-east-1c"]
    count = optional(number)       # 3 → first 3 AZs in the region
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
    role = string # "public" | "private" | "isolated" | "transit_gateway" | "core_network"

    # ── IPv4 Addressing (one of netmask/cidrs/ipam required unless ipv6 native_only) ──
    ipv4 = optional(object({
      netmask        = optional(number)       # auto-calculated from VPC CIDR
      cidrs          = optional(list(string))  # explicit, one per AZ (recommended for prod)
      ipam_pool_id   = optional(string)        # subnet-level IPAM pool
      netmask_length = optional(number)        # with ipam_pool_id
    }))

    # ── IPv6 Addressing ──
    ipv6 = optional(object({
      auto_assign = optional(bool, false)  # calculate /64 from VPC IPv6
      cidrs       = optional(list(string)) # explicit per-AZ
      native_only = optional(bool, false)  # IPv6-only subnet (no IPv4)
    }))

    # ── Naming & Tags ──
    name_prefix = optional(string) # defaults to the map key
    tags        = optional(map(string), {})

    # ── Routing (co-located per subnet group) ──
    routing = optional(object({
      nat_gateway          = optional(bool, false) # route 0.0.0.0/0 → NAT GW
      egress_only_igw      = optional(bool, false) # route ::/0 → EIGW
      internet_gateway     = optional(bool)        # default true for public role
      transit_gateway      = optional(string)      # CIDR or pl-* to route to TGW
      transit_gateway_ipv6 = optional(string)
      core_network         = optional(string)      # CIDR or pl-* to route to Cloud WAN
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
      for k, v in var.subnets :
      !strcontains(k, "/")
    ])
    error_message = "Subnet map keys must not contain '/' (reserved for state key composition)."
  }

  validation {
    condition = length([for k, v in var.subnets : k if v.role == "public"]) <= 1
    error_message = "At most one subnet group may have role 'public'."
  }

  validation {
    condition = length([for k, v in var.subnets : k if v.role == "transit_gateway"]) <= 1
    error_message = "At most one subnet group may have role 'transit_gateway'."
  }

  validation {
    condition = length([for k, v in var.subnets : k if v.role == "core_network"]) <= 1
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
}

# ─────────────────────────────────────────────────────────────────────────────
# NAT GATEWAY — top-level, VPC-wide concern
# ─────────────────────────────────────────────────────────────────────────────

variable "nat_gateway" {
  description = <<-EOT
    NAT Gateway configuration. Controls how many NAT GWs are created and how
    their Elastic IPs are sourced (create new, use BYOIP pool, or inject existing).
    The `az` field is REQUIRED when mode = "single_az" to avoid positional fragility.
  EOT
  type = object({
    mode = optional(string, "none") # "none" | "single_az" | "all_azs"
    az   = optional(string)         # explicit AZ for single_az (eliminates azs[0] fragility)
    eip = optional(object({
      mode             = optional(string, "create") # "create" | "byoip_pool" | "existing"
      public_ipv4_pool = optional(string)           # AWS BYOIP pool ID
      allocation_ids   = optional(map(string), {})  # az -> EIP allocation ID
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
}

# ─────────────────────────────────────────────────────────────────────────────
# EGRESS-ONLY INTERNET GATEWAY (IPv6)
# ─────────────────────────────────────────────────────────────────────────────

variable "egress_only_internet_gateway" {
  description = "Create an Egress-only Internet Gateway for IPv6 private subnet routing."
  type        = bool
  default     = false
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC FLOW LOGS
# ─────────────────────────────────────────────────────────────────────────────

variable "flow_logs" {
  description = "VPC Flow Logs configuration. Set enabled = true to activate."
  type = object({
    enabled      = optional(bool, false)
    destination  = optional(string, "cloudwatch") # "cloudwatch" | "s3"
    traffic_type = optional(string, "ALL")        # "ALL" | "ACCEPT" | "REJECT"
    log_destination = optional(string)            # ARN of CW log group or S3 bucket
    iam_role_arn    = optional(string)            # required for cloudwatch
    log_format      = optional(string)
    retention_days  = optional(number, 30)        # cloudwatch only
    s3_options = optional(object({
      file_format                = optional(string, "plain-text") # "plain-text" | "parquet"
      hive_compatible_partitions = optional(bool, false)
      per_hour_partition         = optional(bool, false)
    }))
    tags = optional(map(string), {})
  })
  default = { enabled = false }

  validation {
    condition     = contains(["cloudwatch", "s3"], try(var.flow_logs.destination, "cloudwatch"))
    error_message = "flow_logs.destination must be 'cloudwatch' or 's3'."
  }

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], try(var.flow_logs.traffic_type, "ALL"))
    error_message = "flow_logs.traffic_type must be 'ALL', 'ACCEPT', or 'REJECT'."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC LATTICE
# ─────────────────────────────────────────────────────────────────────────────

variable "vpc_lattice" {
  description = "VPC Lattice Service Network association. Set to null to skip."
  type = object({
    service_network_identifier = string
    security_group_ids         = optional(list(string), [])
    tags                       = optional(map(string), {})
  })
  default = null
}

# ─────────────────────────────────────────────────────────────────────────────
# GLOBAL TAGS
# ─────────────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}
