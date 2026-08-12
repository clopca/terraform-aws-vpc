# RFC: terraform-aws-vpc v5 — Typed Subnet Contract

> **Status:** Draft / Phase 3 Gate Closed (R1+R2)
>
> **Phase 3 implementation and gate closure (2026-08-12):**
> - Transit Gateway and Cloud WAN attachments use the constant key `"vpc"`.
>   TGW routes depend only on the TGW attachment; Cloud WAN routes depend only
>   on the VPC attachment and its optional accepter, preventing first-apply races
>   without serializing unrelated resources.
> - Cloud WAN constructs `vpc_arn` from scalar identity components. This removes
>   the spurious unknown that caused unrelated replacements. No `ignore_changes`
>   is used: changing the actual VPC identity still performs the correct replace.
> - `flow_logs` keeps CloudWatch create-or-inject convenience. Its generated role
>   scopes write actions to the destination, grants `DescribeLogGroups` on `*`,
>   and protects trust with `aws:SourceAccount` plus `aws:SourceArn`. S3 buckets
>   and Firehose streams are external resources injected through `destination_arn`.
> - `vpc_lattice` uses set semantics for up to five security groups. Private DNS
>   defaults to false and remains an explicit ForceNew choice.
> - The real AWS provider floor is `>= 6.32`, established by the
>   `aws_subnet.ipv4_ipam_pool_id` and `ipv4_netmask_length` arguments. Lattice
>   `private_dns_enabled` separately requires 6.27; TGW security-group referencing
>   alone would require only 5.69.
> - Tier 1 exposes attachment IDs, flow-log IDs, destination ARNs, role ARNs, and
>   the Lattice association ID. Tier 3 exposes created CloudWatch destinations,
>   roles, and policies for advanced composition.
> **Date:** 2026-08-12
> **Authors:** aws-ia team
> **Decisions referenced:** D1–D7 from `00-propuesta-v5.md`
> **Reviews:** `reviews/fase-1.md`, `reviews/fase-2.md`, `reviews/fase-3.md` (R1 + R2 full audit results)

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
- Stable state keys: unified `"name/az"` for all resources
- Create-or-inject pattern for VPC, EIP/NAT, IGW
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
    igw_id           = optional(string)           # null = create; set = inject existing [R1-H2]
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
  description = <<-EOT
    ⚠️  `count` mode is for DEVELOPMENT ONLY [R1-H4].
    For production, always use explicit `names` to guarantee AZ stability.
  EOT
  type = object({
    names = optional(list(string))
    count = optional(number)
  })
}
```

### 3.2 Subnet Contract: `subnets = map(object({...}))`

The core of v5. Each entry is a **subnet group** replicated across AZs.

**State Key Immutability [R1-H1]:** Map keys become part of the Terraform state
address (`aws_subnet.main["key/az"]`). Renaming a key destroys and recreates all
subnets in that group. Users must use `moved` blocks for safe renames. The
`name_prefix` field provides a cosmetic display name decoupled from the state key.

**Multiple Public Groups [R1-C1]:** Unlike v4, multiple subnet groups with
`role = "public"` are supported (e.g., DMZ + edge + GWLB). The `transit_gateway`
and `core_network` roles remain singleton due to AWS API constraints (1 VPC
attachment per TGW/CWAN per VPC).

```hcl
variable "subnets" {
  type = map(object({
    role = string  # "public" | "private" | "isolated" | "transit_gateway" | "core_network"

    # ── Addressing (one required unless ipv6.native_only) ──
    ipv4 = optional(object({
      netmask        = optional(number)       # auto-calculated CIDR (16-28)
      cidrs          = optional(list(string))  # explicit, one per AZ
      ipam_pool_id   = optional(string)
      netmask_length = optional(number)
      cidr_index     = optional(number)       # pinning slot for netmask stability [R1-C2]
    }))
    ipv6 = optional(object({
      auto_assign = optional(bool, false)
      cidrs       = optional(list(string))
      native_only = optional(bool, false)
    }))

    # ── Naming & Tags ──
    name_prefix   = optional(string)  # cosmetic; defaults to map key
    tags          = optional(map(string), {})
    route_table_id = optional(string) # inject one existing shared RT for the group

    # ── Routing (co-located, list-based destinations) [R1-C3] ──
    routing = optional(object({
      nat_gateway          = optional(bool, false)
      egress_only_igw      = optional(bool, false)
      internet_gateway     = optional(bool)           # null = auto (true for public) [R2-H3]
      dns64                = optional(bool, false)    # Creates 64:ff9b::/96 -> NAT GW; NAT required
      transit_gateway      = optional(list(string))   # list of CIDRs/prefix-list IDs [R1-C3]
      transit_gateway_ipv6 = optional(list(string))
      core_network         = optional(list(string))   # list of CIDRs/prefix-list IDs [R1-C3]
      core_network_ipv6    = optional(list(string))
    }), {})

    # ── Role-specific blocks ──
    public_options = optional(object({
      map_public_ip = optional(bool, true)
    }))

    transit_gateway_options = optional(object({
      id                              = string
      default_route_table_association = optional(bool, true)
      default_route_table_propagation = optional(bool, true)
      appliance_mode_support          = optional(bool, false)
      dns_support                     = optional(bool, true)
      security_group_referencing      = optional(bool, true)  # requires provider >= 5.69 [R2-C1]
    }))

    core_network_options = optional(object({
      id                 = string
      arn                = optional(string)  # auto-derived if omitted
      appliance_mode     = optional(bool, false)
      require_acceptance = optional(bool, false)
      accept_attachment  = optional(bool, false) # explicit true supports same-account acceptance only
    }))
  }))
}
```

### 3.3 NAT Gateway (typed, AZ-explicit, create-or-inject)

```hcl
variable "nat_gateway" {
  type = object({
    mode              = optional(string, "none")  # "none" | "single_az" | "all_azs"
    az                = optional(string)          # required when mode = "single_az"
    connectivity_type = optional(string, "public") # "public" | "private" (private NAT, no EIP)
    subnet_group      = optional(string)           # explicit host group; null = first compatible group
    existing_ids      = optional(map(string))      # az → nat_gw_id for inject mode [R1-H2]
    eip = optional(object({
      mode             = optional(string, "create")
      public_ipv4_pool = optional(string)
      allocation_ids   = optional(map(string))  # nullable, required for "existing" [R2-H2]
    }), { mode = "create" })
  })
  default = { mode = "none" }
}
```

### 3.3.1 Route Table and NAT Placement Injection Semantics

- `subnets.<group>.route_table_id` injects one existing route table shared by every
  AZ subnet in the group. The module skips `aws_route_table` creation, associates
  those subnets to the injected table, and adds the routes declared in `routing`
  to that existing table. Callers must avoid destination conflicts with routes
  managed outside the module.
- Because a single shared route table cannot select a different NAT Gateway per AZ,
  injected tables that request `nat_gateway` or `dns64` require
  `nat_gateway.mode = "single_az"`. Use module-created tables for per-AZ NAT.
- `nat_gateway.subnet_group` pins placement of created NAT Gateways. It must name a
  `public` group for public NAT or a `private` group for private NAT. Null defaults
  to the first compatible group alphabetically for convenience; production callers
  should always set it to prevent relocation when subnet groups are added.
- `dns64 = true` creates both the subnet DNS64 flag and the required
  `64:ff9b::/96 -> NAT Gateway` route. It fails early when NAT is disabled.

### 3.4 State Keys — Unified `"name/az"`

| Resource | v4 Key | v5 Key |
|----------|--------|--------|
| `aws_subnet.public` | `"us-east-1a"` | `"public/us-east-1a"` |
| `aws_subnet.private` | `"private/us-east-1a"` | `"app/us-east-1a"` (user's key) |
| `aws_subnet.tgw` | `"us-east-1a"` | `"tgw/us-east-1a"` |
| `aws_subnet.cwan` | `"us-east-1a"` | `"cwan/us-east-1a"` |
| `aws_eip.nat` | `"us-east-1a"` | `"nat/us-east-1a"` |
| `aws_nat_gateway.main` | `"us-east-1a"` | `"nat/us-east-1a"` |
| `aws_route_table.*` | follows parent | follows parent |

### 3.5 CIDR Calculation Algorithm [R1-C2]

**Deterministic allocation with two-tier pinning:**

1. **Pinned groups** (`cidr_index` set): Allocated first using the index as
   network-number offset. Immune to addition/removal of other groups.
2. **Unpinned groups** (`cidr_index` null): Allocated sequentially after highest
   pinned slot, sorted by netmask DESC then alphabetically.

**Stability guarantees:**
- Pinned groups: NEVER shift regardless of other group changes.
- Unpinned groups: May shift if a group that sorts before them is added/removed.
- AZ addition: Only new AZ slots are appended within each group.

**Production recommendation:** Use explicit `cidrs` for immutable allocations,
`cidr_index` for stable auto-calculation, bare `netmask` for disposable environments.

### 3.6 Outputs — 3 Tiers

#### Tier 1: Stable Contract (semver-protected)

```hcl
output "vpc_id" {}
output "vpc_cidr_block" {}
output "azs" {}
output "subnet_ids_by_group" {}             # map(group_name, list(id))
output "subnet_ids_by_group_by_az" {}       # map(group_name, map(az, id))
output "subnet_cidrs_by_group_by_az" {}     # map(group_name, map(az, cidr))
output "subnet_arns_by_group_by_az" {}      # map(group_name, map(az, arn))
output "subnet_ids_by_semantic_role" {}     # map(role, list(id)) [R1-H3]
output "subnet_ids_by_semantic_role_by_az" {} # map(role, map(az, list(id))) [R1-H3]
output "nat_gateway_ids" {}                 # map(az, nat_id)
output "nat_public_ips" {}                  # map(az, ip)
output "internet_gateway_id" {}
output "egress_only_igw_id" {}              # EIGW ID (null if not created)
output "route_table_ids_by_group_by_az" {}  # map(group, map(az, rt_id))
output "route_table_ids_by_semantic_role" {} # map(role, list(rt_id))
output "transit_gateway_attachment_id" {}
output "core_network_attachment_id" {}
output "flow_log_ids" {}                    # map(key, flow_log_id)
output "flow_log_destination_arns" {}       # map(key, destination_arn)
output "flow_log_role_arns" {}              # map(key, role_arn|null)
output "vpc_lattice_service_network_association_id" {}
```

#### Tier 2: Deprecated Legacy (present in v5, removed in v6)

```hcl
output "subnet_ids_by_role" {}         # DEPRECATED: renamed to subnet_ids_by_group
output "subnet_ids_by_role_by_az" {}   # DEPRECATED: renamed to subnet_ids_by_group_by_az
output "subnet_cidrs_by_role_by_az" {} # DEPRECATED: renamed to subnet_cidrs_by_group_by_az
```

#### Tier 3: Escape Hatch (no semver guarantee)

```hcl
output "resources" {}  # Full resource objects, UNSTABLE
```

### 3.7 Cross-Variable Invariants (enforced via preconditions) [R2-C2, R2-C3, R2-H1]

These cannot be expressed as variable validations (Terraform limitation: no cross-var refs).
They are enforced as `lifecycle.precondition` on the relevant resource, which means they
fire at plan time when values are known. With `availability_zones.count`, the selected
AZ names come from `data.aws_availability_zones`; preconditions that depend on that set
are unknown during the initial plan and Terraform defers them to apply time. Production
callers should use explicit `names` for stable AZ identity and plan-time diagnostics.

1. **cidrs length == AZ count** [R2-C2]: `terraform_data.cidrs_az_count_validation`
2. **nat_gateway.az ∈ resolved AZs** [R2-C3]: `terraform_data.nat_gateway_az_validation`
3. **Subnet addressing exists** [R2-H1]: `aws_subnet.main` precondition

### 3.8 Provider Floor [R2-H2]

Required AWS provider: `>= 6.32`.

The limiting feature is subnet IPAM: the v5 implementation sets
`ipv4_ipam_pool_id` and `ipv4_netmask_length` on `aws_subnet`, including null in
non-IPAM paths, and those schema arguments require AWS provider 6.32. The other
Phase 3 additions have lower floors: `private_dns_enabled` on the VPC Lattice
association requires 6.27, while TGW `security_group_referencing_support` requires
5.69. A consumer locked to provider 5.x can satisfy neither the published schema
nor validate the complete module, so v5 intentionally raises the major floor.

### 3.9 Isolated Role Semantics

`isolated` is functionally `private` with a routing guard. It prevents accidental
routing configuration (including TGW/CWAN routes). Use `role = "private"` for subnets
that need selective routing without internet access.

### 3.10 Phase 3 ADRs

#### ADR-F3-1 — S3 and Firehose flow-log destinations are external

**Decision:** the VPC module creates only `aws_flow_log` plus the optional
CloudWatch log group and VPC Flow Logs role. For `destination_type = "s3"` or
`"kinesis"`, callers must provide `destination_arn` for an externally managed
bucket or Firehose delivery stream.

**Reasoning:** owning durable log destinations would make this module responsible
for retention, lifecycle expiration, KMS keys and grants, bucket ownership and
policies, Firehose buffering, and cross-account governance. Those policies vary by
organization and belong in dedicated logging modules. This is a pre-publication
contract decision, so no compatibility shim is required.

#### ADR-F3-2 — Cloud WAN acceptance and route staging

`accept_attachment` defaults to false. Setting it true is supported only when the
Core Network owner account is the same account as the module provider. A shared
cross-account Core Network must be accepted with an owner-account provider outside
this module. When external acceptance is required, callers first apply the
attachment without Core Network routes, accept it externally, then set
`require_acceptance = false` and add routes. A precondition rejects routes during
the pending external-acceptance stage.

Core Network ARNs are validated as complete
`arn:<partition>:networkmanager::<12-digit-account>:core-network/<id>` values and
must match the configured ID.

#### ADR-F3-3 — VPC Lattice DNS and security groups

`private_dns_enabled` defaults to false to avoid an implicit ForceNew DNS choice.
Changing it replaces the association by provider design. Security groups are a
set, because ordering is meaningless, and the contract rejects more than the AWS
quota of five. Additional DNS preference/domain fields remain future additive
contract work after provider behavior and migration semantics are reviewed.

#### ADR-F3-4 — Flow Logs validation boundary

The contract validates supported CloudWatch retention periods, non-empty optional
ARNs, and mandatory external destination ARNs for S3/Firehose. It does not infer
cross-account ownership from an ARN or attempt to prove IAM permissions at plan
time; those are runtime/account-policy concerns. `deliver_cross_account_role_arn`
is accepted as an explicit non-empty ARN and remains caller-owned.

### 3.11 Import and adoption

Existing resources can be adopted without adding unmanaged-resource bypasses:

```shell
terraform import 'module.vpc.aws_ec2_transit_gateway_vpc_attachment.this["vpc"]' tgw-attach-0123456789abcdef0
terraform import 'module.vpc.aws_networkmanager_vpc_attachment.this["vpc"]' attachment-0123456789abcdef0
terraform import 'module.vpc.aws_vpclattice_service_network_vpc_association.this["vpc"]' snva-0123456789abcdef0
terraform import 'module.vpc.aws_flow_log.this["audit"]' fl-0123456789abcdef0
```

Use the caller-owned `flow_logs` map key in the final address. Imported attachments
retain the singleton `"vpc"` address.

---

## 4. Migration Path v4 → v5

*(unchanged from original RFC — see v4→v5 migration guide for moved blocks strategy)*

## 5. Open Questions (Resolved)

1. ~~Should `isolated` be a distinct role?~~ → **YES.** Kept for validation guard value.
2. ~~Multiple public groups?~~ → **YES.** [R1-C1] Singleton removed.
3. ~~Generator script for moved blocks?~~ → Generator approach kept (dynamic `moved` experimental).
4. ~~NAT top-level vs nested?~~ → **Top-level confirmed** (VPC-wide concern).

## 6. Future Work (TODO)

- **Phase 2**: Route table injection via `subnets[*].route_table_id` — ✅ DONE
- **Phase 2**: NAT Gateway injection via `existing_ids` — ✅ DONE
- **Phase 2**: IGW injection via `vpc.igw_id` — ✅ DONE (Phase 1)
- **Phase 2**: EIGW creation + routing — ✅ DONE
- **Phase 2**: Private NAT (connectivity_type) — ✅ DONE
- **Phase 2**: DNS64/NAT64 support — ✅ DONE
- **Phase 2**: Route tables co-located per group/az — ✅ DONE
- **Phase 5**: `stable_key` alternative to map-key-as-state-identity — evaluate need post-launch [R1-H1]
