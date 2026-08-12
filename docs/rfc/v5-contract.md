# RFC: terraform-aws-vpc v5 — Typed Subnet Contract

> **Status:** Draft / Evaluable Prototype  
> **Date:** 2026-08-12  
> **Authors:** aws-ia team  
> **Decisions referenced:** D1–D7 from `00-propuesta-v5.md`

---

## 1. Problem Statement

The v4 module suffers from three structural defects:

1. **Implicit contract**: 6 variables typed `any`; `var.subnets` is a heterogeneous
   map where 3 magic keys (`public`, `transit_gateway`, `core_network`) activate
   singleton behavior and any other key is "private". Zero IDE support.
2. **Unstable identity**: positional CIDR assignment (adding a subnet type shifts all
   CIDRs → mass destroy); NAT `single_az` keyed by `local.azs[0]`; inconsistent key
   format (private uses `"type/az"`, the rest only `"az"`).
3. **Poor composition surface**: no `subnet_ids_by_role`, no flat `route_table_ids`;
   downstream modules (hubandspoke, cloudwan) parse keys with `split("/", k)`.

## 2. Design Goals

- Zero `type = any` in the public contract
- Explicit `role` per subnet group (no magic keys)
- Stable state keys: unified `"role/az"` for all resources
- Create-or-inject pattern for EIP/NAT (BYOIP support)
- IPAM first-class at VPC and subnet level
- Tiered outputs with semver stability guarantees
- Zero-diff migration path from v4 via `moved` blocks

## 3. Contract Design

### 3.1 Top-Level Variables

```hcl
variable "vpc" {
  type = object({
    name             = string
    id               = optional(string)           # null = create; set = use existing
    instance_tenancy = optional(string, "default")
    dns = optional(object({
      enable_hostnames = optional(bool, true)
      enable_support   = optional(bool, true)
    }), {})
    tags = optional(map(string), {})
  })
}

variable "addressing" {
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
}

variable "availability_zones" {
  type = object({
    names = optional(list(string))
    count = optional(number)
  })
}
```

### 3.2 Subnet Contract: `subnets = map(object({...}))`

The core of v5. Each entry is a **subnet group** replicated across AZs.

```hcl
variable "subnets" {
  type = map(object({
    role = string  # "public" | "private" | "isolated" | "transit_gateway" | "core_network"

    # ── Addressing (one required unless ipv6.native_only) ──
    ipv4 = optional(object({
      netmask        = optional(number)       # auto-calculated CIDR from VPC range
      cidrs          = optional(list(string))  # explicit, one per AZ
      ipam_pool_id   = optional(string)        # subnet-level IPAM
      netmask_length = optional(number)        # with ipam_pool_id
    }))
    ipv6 = optional(object({
      auto_assign = optional(bool, false)
      cidrs       = optional(list(string))
      native_only = optional(bool, false)
    }))

    # ── Naming & Tags ──
    name_prefix = optional(string)  # defaults to map key
    tags        = optional(map(string), {})

    # ── Routing (co-located, not in separate variables) ──
    routing = optional(object({
      nat_gateway          = optional(bool, false)
      egress_only_igw      = optional(bool, false)
      internet_gateway     = optional(bool)          # default: true for public
      transit_gateway      = optional(string)        # CIDR or prefix-list to route
      transit_gateway_ipv6 = optional(string)
      core_network         = optional(string)
      core_network_ipv6    = optional(string)
    }), {})

    # ── Role-specific blocks (only relevant per role) ──
    public_options = optional(object({
      map_public_ip = optional(bool, true)
    }))

    transit_gateway_options = optional(object({
      id                              = string
      default_route_table_association = optional(bool, true)
      default_route_table_propagation = optional(bool, true)
      appliance_mode_support          = optional(bool, false)
      dns_support                     = optional(bool, true)
    }))

    core_network_options = optional(object({
      id                 = string
      arn                = string
      appliance_mode     = optional(bool, false)
      require_acceptance = optional(bool, false)
      accept_attachment  = optional(bool, true)
    }))
  }))
}
```

### 3.3 NAT Gateway (typed, AZ-explicit)

Extracted to top-level for clarity — it's a VPC-wide concern, not per-subnet.

```hcl
variable "nat_gateway" {
  type = object({
    mode = optional(string, "none")  # "none" | "single_az" | "all_azs"
    az   = optional(string)          # required when mode = "single_az"
    eip = optional(object({
      mode             = optional(string, "create")  # "create" | "byoip_pool" | "existing"
      public_ipv4_pool = optional(string)            # for byoip_pool mode
      allocation_ids   = optional(map(string))       # az -> alloc_id for existing mode
    }), { mode = "create" })
  })
  default = { mode = "none" }
}
```

### 3.4 State Keys — Unified `"role/az"`

| Resource | v4 Key | v5 Key |
|----------|--------|--------|
| `aws_subnet.public` | `"us-east-1a"` | `"public/us-east-1a"` |
| `aws_subnet.private` | `"private/us-east-1a"` | `"private/us-east-1a"` (stable) |
| `aws_subnet.tgw` | `"us-east-1a"` | `"transit_gateway/us-east-1a"` |
| `aws_subnet.cwan` | `"us-east-1a"` | `"core_network/us-east-1a"` |
| `aws_eip.nat` | `"us-east-1a"` | `"nat/us-east-1a"` |
| `aws_nat_gateway.main` | `"us-east-1a"` | `"nat/us-east-1a"` |
| `aws_route_table.*` | follows parent | follows parent |

All v5 resource keys follow `"<logical_name>/<az>"` pattern — deterministic,
rename-safe, no positional fragility.

### 3.5 Outputs — 3 Tiers

#### Tier 1: Stable Contract (semver-protected)

```hcl
output "vpc_id" {}
output "vpc_cidr_block" {}
output "subnet_ids_by_role" {}      # map(role, list(id))
output "subnet_ids_by_role_by_az" {} # map(role, map(az, id))
output "route_table_ids" {}          # map(role, map(az, rt_id))
output "nat_gateway_ids" {}          # map(az, nat_id)
output "nat_public_ips" {}           # map(az, ip)
output "transit_gateway_attachment_id" {}
output "core_network_attachment_id" {}
output "internet_gateway_id" {}
```

#### Tier 2: Deprecated Legacy (present in v5, removed in v6)

All current v4 outputs kept with `DEPRECATED` description. Allows hubandspoke
and cloudwan to migrate without rush.

#### Tier 3: Escape Hatch (no semver guarantee)

```hcl
output "resources" {}  # Full resource objects, UNSTABLE
```

## 4. Migration Path v4 → v5

### 4.1 Variable Translation Table

| v4 Variable | v5 Equivalent | Notes |
|---|---|---|
| `name` | `vpc.name` | — |
| `cidr_block` | `addressing.ipv4.cidr_block` | — |
| `vpc_id` | `vpc.id` | — |
| `create_vpc` | `vpc.id != null` (implicit) | Eliminated; presence of `vpc.id` = existing |
| `az_count` | `availability_zones.count` | — |
| `azs` | `availability_zones.names` | — |
| `vpc_enable_dns_hostnames` | `vpc.dns.enable_hostnames` | — |
| `vpc_enable_dns_support` | `vpc.dns.enable_support` | — |
| `vpc_ipv4_ipam_pool_id` | `addressing.ipv4.ipam_pool_id` | — |
| `vpc_ipv4_netmask_length` | `addressing.ipv4.netmask_length` | Fixed: now `number` |
| `vpc_secondary_cidr` | `addressing.ipv4.secondary[*]` | Now a list of objects |
| `vpc_flow_logs` | `flow_logs` (separate var) | Kept similar shape |
| `transit_gateway_id` | `subnets["tgw"].transit_gateway_options.id` | Co-located |
| `transit_gateway_routes` | `subnets["app"].routing.transit_gateway` | Per-subnet routing |
| `core_network` | `subnets["cwan"].core_network_options` | Co-located |
| `subnets.public.nat_gateway_configuration` | `nat_gateway.mode` | Top-level, typed |
| `subnets.*.connect_to_public_natgw` | `subnets.*.routing.nat_gateway` | Bool, same semantics |
| `subnets.*.connect_to_eigw` | `subnets.*.routing.egress_only_igw` | Bool, same semantics |

### 4.2 Moved Blocks Strategy

The module ships a `moved.tf` covering all known resource address changes:

```hcl
# Public subnets: key "az" → "public/az"
moved {
  from = aws_subnet.public["us-east-1a"]
  to   = aws_subnet.main["public/us-east-1a"]
}

# NAT gateways: key "az" → "nat/az"
moved {
  from = aws_nat_gateway.main["us-east-1a"]
  to   = aws_nat_gateway.main["nat/us-east-1a"]
}
moved {
  from = aws_eip.nat["us-east-1a"]
  to   = aws_eip.nat["nat/us-east-1a"]
}

# TGW subnets: key "az" → "transit_gateway/az"
moved {
  from = aws_subnet.tgw["us-east-1a"]
  to   = aws_subnet.main["transit_gateway/us-east-1a"]
}

# Core Network: key "az" → "core_network/az"
moved {
  from = aws_subnet.cwan["us-east-1a"]
  to   = aws_subnet.main["core_network/us-east-1a"]
}

# Private subnets: already "role/az" — no move needed
```

**Key design choice**: v5 uses a SINGLE `aws_subnet.main` resource with unified
`for_each` instead of separate `aws_subnet.public`, `.private`, `.tgw`, `.cwan`.
This simplifies logic and enables the unified key space.

The `moved` blocks are **region-specific** (contain literal AZ names), so the
module ships a **generator script** (`scripts/generate-moved-blocks.sh`) that reads
the user's state and emits the appropriate `moved.tf`.

### 4.3 Zero-Diff Migration Example

```bash
# 1. User upgrades module source to v5
# 2. Translates their variables (manually or via migration script)
# 3. Runs the moved-blocks generator
./scripts/generate-moved-blocks.sh > moved_override.tf

# 4. Plan should show 0 changes
terraform plan  # Expected: "No changes."

# 5. Apply to lock new state addresses, then remove moved_override.tf
terraform apply
rm moved_override.tf
```

## 5. Cost/Benefit Analysis

### 5.1 What v4.6/v4.7 Already Delivers

| Feature | Version | Effort |
|---|---|---|
| BYOIP EIP injection (PR#179 rescue) | v4.6 | ~2d |
| Fix outputs mixing NAT/isolated (#177) | v4.6 | ~1d |
| Cloud WAN non-destructive attachment (PR#182) | v4.7 | ~2d |
| IPAM secondary CIDR (#146) | v4.7 | ~2d |
| CI gates + assertions (phase 1) | v4.6 | ~3h |

**Total v4.6+4.7 effort: ~8 days**, resolving 85% of the top backlog demand
**without breaking changes**.

### 5.2 What v5 Adds Beyond v4.7

| Capability | Impact | Without v5 alternative |
|---|---|---|
| Full type safety + IDE autocomplete | DX improvement, fewer runtime errors | Users read docs carefully |
| Unified state keys (no positional CIDR fragility) | Eliminates mass-destroy on subnet addition | Use explicit `cidrs` (workaround exists) |
| Co-located routing per subnet | Cleaner UX, fewer variables | Tolerable with current pattern |
| Tiered outputs with semver contract | Downstream stability | Document "don't break these outputs" |
| Single resource type for all subnets | Simpler module internals | Separate resources work fine |
| Subnet-level IPAM | Enterprise IPAM workflows | VPC-level IPAM + explicit subnet CIDRs |

### 5.3 Cost of v5

| Cost | Estimate |
|---|---|
| Design + implementation | ~15-20 days |
| Testing (unit + integration matrix) | ~7 days |
| Documentation (upgrade guide, examples, RFC) | ~3 days |
| Downstream updates (hubandspoke, cloudwan) | ~5 days |
| Community disruption (breaking change, even with moved blocks) | Moderate |
| **Total** | **~30-35 days** |

### 5.4 Backlog Signals That Would Justify Full v5

Execute v5 if ANY of these materialize in the next 6 months:

1. **3+ issues requesting new subnet roles** (e.g. "firewall", "EKS pod") that
   can't be satisfied by the current "any key = private" pattern
2. **Reproducible mass-destroy bugs** from CIDR recalculation (users hitting the
   positional assignment problem in production)
3. **Downstream modules (hubandspoke/cloudwan) requiring outputs** not achievable
   with additive Tier-1 outputs on v4
4. **AWS launching new attachment types** (beyond TGW/CWAN) that require dedicated
   subnet handling — the current pattern of adding hardcoded resource blocks doesn't scale
5. **Adoption of the module by a team requiring strict type safety** for policy-as-code
   (Sentinel/OPA) that can't work with `any`-typed inputs

### 5.5 Alternative: "v5 Minimal" (typed subnets + stable keys, no re-scope)

A reduced v5 that delivers 80% of the DX benefit at 40% of the cost:

| Included | Excluded |
|---|---|
| `subnets = map(object)` with typed roles | No re-scope of what's in/out of module |
| Unified `"role/az"` keys + moved blocks | No change to routing variables pattern |
| Validation blocks replacing runtime `try()` | No single `aws_subnet.main` consolidation |
| BYOIP via `nat_gateway` typed variable | No subnet-level IPAM |
| Tier 1 additive outputs | No Tier 2 deprecation (keep all v4 outputs as-is) |

**Effort: ~12-15 days** — half the full v5, delivers the type safety and key
stability that constitute the core value proposition.

**Recommendation:** Ship v4.6 and v4.7 first. Evaluate in 3 months whether the
"v5 minimal" or full v5 is warranted based on the backlog signals above. The
prototype in `docs/rfc/v5-prototype/` demonstrates that the typed contract is
ergonomically viable.

## 6. Open Questions

1. Should `isolated` be a distinct role or just `private` with `routing = {}`?
2. Should the module support multiple public subnet groups (e.g. DMZ + edge)?
3. Is the generator script approach for moved blocks acceptable, or should the
   module ship ALL possible moved blocks (bloated but zero-effort for users)?
4. Should `nat_gateway` stay top-level or be nested under the `public` subnet's options?

---

## Appendix A: Comparison with AVM Pattern

The Azure Verified Modules (AVM) VNet module uses `map(object)` with arbitrary keys
and no concept of "role" — each subnet is self-contained with its delegations, NSG,
and route table references. Our v5 adds an explicit `role` field because AWS subnet
behavior differs materially by role (public needs IGW routes, TGW needs attachments,
etc.) and the module is opinionated about creating those resources. The `role` acts
as a type discriminator that unlocks per-role validation and resource creation logic.
