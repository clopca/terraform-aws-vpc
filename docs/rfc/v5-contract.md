# RFC: terraform-aws-vpc v5 — Typed Subnet Contract

> **Status:** Candidate contract; complete local gate green, live AWS revalidation pending
> **Date:** 2026-08-13
> **Technical snapshot:** `007e529` on `explore/v5-typed-contract` before this status-only update
> **Local evidence:** `terraform test` 118/118, TFLint 0 findings, fmt clean, module + 11 examples init/validate 12/12 locally and from `git archive`, README external init green
> **AWS revalidation:** pending by design; this remediation made no AWS API calls and makes no fresh apply/zero-diff/destroy claim
>
> Historical remediation detail remains in `docs/rfc/reviews/` as an appendix, not as current release status.

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
- Create-or-inject pattern for every managed boundary resource
- IPAM first-class at VPC and subnet level
- Tiered outputs with semver stability guarantees
- Zero-diff migration path from v4 via `moved` blocks

## 3. Contract Design

### 3.1 Top-Level Variables

```hcl
variable "vpc" {
  type = object({
    name             = string
    create           = optional(bool, true)       # plan-known ownership selector
    id               = optional(string)           # required when create=false; may be computed
    igw_create       = optional(bool, true)       # plan-known ownership selector
    igw_id           = optional(string)           # required for needed injected IGW; may be computed
    igw_name_format  = optional(string, "{vpc}-igw")
    igw_tags         = optional(map(string), {})
    eigw_create      = optional(bool, true)       # plan-known ownership selector
    eigw_id          = optional(string)           # required for needed injected EIGW; may be computed
    eigw_name_format = optional(string, "{vpc}-eigw")
    eigw_tags        = optional(map(string), {})
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
    primary = object({
      cidr_block     = optional(string)
      ipam_pool_id   = optional(string)
      netmask_length = optional(number)
    })
    secondary = optional(map(object({
      ipv4 = optional(object({
        create         = optional(bool, true)
        association_id = optional(string)
        cidr_block     = optional(string)
        ipam_pool_id   = optional(string)
        netmask_length = optional(number)
      }))
      ipv6 = optional(object({
        create          = optional(bool, true)
        association_id  = optional(string)
        amazon_assigned = optional(bool, false)
        cidr_block      = optional(string)
        ipam_pool_id    = optional(string)
        netmask_length  = optional(number)
      }))
    })), {})
  })
}

variable "availability_zones" {
  description = <<-EOT
    `count` sorts eligible AZs and selects exactly the first N.
    ⚠️  `count` mode is for DEVELOPMENT ONLY.
    For production, always use explicit `names` to guarantee AZ stability.
  EOT
  type = object({
    names = optional(list(string))
    count = optional(number)
  })
}
```

D6 adds two typed top-level contracts. `vpc_block_public_access` controls the
regional options singleton and stable-keyed exclusions; options and each
exclusion independently select create or inject. `dhcp_options` likewise
selects create or inject and always manages the association to this VPC when
enabled. Their complete generated schemas are part of the module README.

### 3.2 Subnet Contract: `subnets = map(object({...}))`

The core of v5. Each entry is a **subnet group** replicated across AZs.

**State Key Immutability:** Map keys become part of the Terraform state
address (`aws_subnet.main["key/az"]`). Renaming a key destroys and recreates all
subnets in that group. Users must use `moved` blocks for safe renames. The
`name_prefix` field provides a cosmetic display name decoupled from the state key.

**Multiple Public Groups:** Unlike v4, multiple subnet groups with
`role = "public"` are supported (e.g., DMZ + edge + GWLB). The `transit_gateway`
and `core_network` roles remain singleton due to AWS API constraints (1 VPC
attachment per TGW/CWAN per VPC).

```hcl
variable "subnets" {
  type = map(object({
    role         = string  # "public" | "private" | "isolated" | "transit_gateway" | "core_network"
    create       = optional(bool, true)
    existing_ids = optional(map(string)) # AZ -> subnet ID when create=false

    # ── Addressing (one required unless ipv6.native_only) ──
    ipv4 = optional(object({
      netmask        = optional(number)       # auto-calculated CIDR (16-28)
      cidrs_by_az    = optional(map(string))  # explicit, one per AZ
      ipam_pool_id   = optional(string)
      netmask_length = optional(number)
      cidr_index         = optional(number)   # pinning slot for netmask stability
      secondary_cidr_key = optional(string)   # stable IPv4 entry in addressing.secondary
    }))
    ipv6 = optional(object({
      secondary_cidr_key = optional(string) # semantically required; selected IPv6 entry in addressing.secondary
      auto_assign    = optional(bool, false) # also calculates a parent-derived /64 when no other source is set
      cidrs_by_az    = optional(map(string))
      ipam_pool_id   = optional(string)
      netmask_length = optional(number)      # 64 for subnet IPAM
      native_only    = optional(bool, false)
      cidr_index     = optional(number)      # six-AZ pinning slot, analogous to IPv4
    }))

    # ── Naming & Tags ──
    name_prefix             = optional(string)  # cosmetic; defaults to map key
    name_format             = optional(string)  # complete Name; {vpc}/{group}/{az}
    route_table_name_format = optional(string)  # defaults to name_format
    tags                    = optional(map(string), {})
    manage_route_table      = optional(bool, true)
    route_table_key         = optional(string) # caller-owned physical identity when injecting
    route_table_id          = optional(string) # effective ID; may be computed

    # ── Routing (co-located, list-based destinations) ──
    routing = optional(object({
      nat_gateway          = optional(bool, false)
      egress_only_igw      = optional(bool, false)
      internet_gateway     = optional(bool)           # null = auto (true for public)
      dns64                = optional(bool, false)    # Creates 64:ff9b::/96 -> NAT GW; NAT required
      transit_gateway      = optional(list(string))   # list of CIDRs/prefix-list IDs
      transit_gateway_ipv6 = optional(list(string))
      core_network         = optional(list(string))   # list of CIDRs/prefix-list IDs
      core_network_ipv6    = optional(list(string))
    }), {})

    # ── Role-specific blocks ──
    public_options = optional(object({
      map_public_ip = optional(bool, false)
    }))

    transit_gateway_options = optional(object({
      id                              = string
      create                          = optional(bool, true)
      attachment_id                   = optional(string)
      default_route_table_association = optional(bool, true)
      default_route_table_propagation = optional(bool, true)
      appliance_mode_support          = optional(bool, false)
      dns_support                     = optional(bool, true)
      security_group_referencing      = optional(bool, true)  # requires provider >= 5.69
    }))

    core_network_options = optional(object({
      id                 = string
      arn                = optional(string)  # auto-derived if omitted
      create             = optional(bool, true)
      attachment_id      = optional(string)
      appliance_mode     = optional(bool, false)
      require_acceptance = optional(bool, false)
      accept_attachment  = optional(bool, false) # explicit true supports same-account acceptance only
      create_accepter    = optional(bool, true)
      accepter_id        = optional(string)
    }))
  }))
}
```

### 3.2.1 Reserved additive extension points

The pre-freeze contract reserves optional growth inside existing nested objects,
not new parallel top-level APIs:

- `subnets[*].dns_on_launch`: A/AAAA resource-name records and private hostname type;
- `subnets[*].core_network_options`: DNS support, security-group referencing, and
  routing policy label;
- `nat_gateway.eip`: public IPAM pool allocation alongside create/BYOIP/existing.

These are documented reservations, not accepted no-op inputs in 5.0. Adding typed
optional attributes inside these existing objects is the compatible 5.x path.

### 3.3 NAT Gateway (typed, zonal or VPC-level, create-or-inject)

```hcl
variable "nat_gateway" {
  type = object({
    mode              = optional(string, "none")  # "none" | "single_az" | "all_azs" | "regional"
    create            = optional(bool, true)      # false injects existing_ids; plan-known
    az                = optional(string)          # required only when mode = "single_az"
    connectivity_type = optional(string, "public") # regional requires "public"
    subnet_group      = optional(string)          # zonal host group; regional requires null
    existing_ids      = optional(map(string))     # zonal: az → id; regional: { regional = id }
    name_format       = optional(string, "{vpc}-nat-{az}")
    tags              = optional(map(string), {})
    eip = optional(object({
      mode             = optional(string, "create")
      public_ipv4_pool = optional(string)
      allocation_ids   = optional(map(string))  # nullable, required for "existing"
      name_format      = optional(string)        # defaults to NAT format
      tags             = optional(map(string), {})
    }), { mode = "create" })
  })
  default = { mode = "none" }
}
```

### 3.3.1 Route Table and NAT Placement Injection Semantics

- `subnets.<group>.manage_route_table=false` plus `route_table_key` and
  `route_table_id` injects an existing table. `route_table_key` is caller-owned
  physical identity: all groups sharing a table reuse that key and ID. The module
  associates every subnet but unions routing intent and creates each route/endpoint
  association once per physical key. Different IDs under one key, or one known ID
  under multiple keys, fail contract validation.
- Because a single shared route table cannot select a different zonal NAT Gateway
  per AZ, injected tables that request `nat_gateway` or `dns64` reject
  `nat_gateway.mode = "all_azs"`. They support `single_az` or `regional`, where one
  physical NAT ID serves every configured AZ key.
- Zonal `nat_gateway.subnet_group` pins placement of created NAT Gateways. It must
  name a `public` group for public NAT or a `private` group for private NAT. Null
  defaults to the first compatible group alphabetically for convenience;
  production callers should set it to prevent relocation when groups are added.
- Regional mode creates one public `aws_nat_gateway` with
  `availability_mode = "regional"`, `vpc_id`, and no `subnet_id`; it rejects `az`,
  `subnet_group`, and private connectivity. No public host subnet is required.
  `eip.mode = "create"` delegates IP/AZ management to AWS. `existing` and
  `byoip_pool` use manual `availability_zone_address` blocks for every configured
  AZ; existing EIPs remain caller-owned and BYOIP EIPs are module-owned.
- Regional routes and `nat_gateway_ids` repeat one physical NAT ID under every
  configured AZ key. Address outputs retain every scaled address under
  `<az>/<allocation-id>` keys, while dedicated outputs expose the AWS-managed route
  table and complete address records grouped by AZ.
- `dns64 = true` creates both the subnet DNS64 flag and the required
  `64:ff9b::/96 -> NAT Gateway` route. It fails early when NAT is disabled.

### 3.3.2 Resource Name and tag precedence

Display names are independent from state identity. Subnet groups accept a complete
`name_format`; route tables inherit it unless `route_table_name_format` is set.
NAT/EIP formats resolve against the selected host group, while IGW/EIGW formats
resolve at the VPC boundary. Flow Logs use `{vpc}`/`{key}`; the log-group format
inherits the Flow Log format unless independently set. An empty Flow Log format
omits `Name` and removes caller `Name` keys, which is required to reproduce v4's
untagged generated log group. Other supported placeholders are `{vpc}`, `{group}`,
and `{az}` where meaningful; literal strings are valid. A non-empty generated
`Name` wins over user maps so a duplicate cannot defeat the naming contract.

Every taggable resource uses an explicit `merge`. Effective precedence is AWS
provider `default_tags` < `var.tags` < resource/group tags < non-empty generated `Name`.
Provider `>= 6.29` is beyond the historical pre-5.0 `default_tags` identical-tag
perpetual-diff defects. No `ignore_changes` is used: changing provider defaults is
a real tag mutation and must be baselined on v4 before migration. Untaggable AWS
resources and validation-only `terraform_data` have no tag argument by schema.

### 3.3.8 ADR-R9-A5 — isolated means no Internet, not no routes

**Decision:** isolated groups may associate S3/DynamoDB gateway endpoints while
Internet, NAT, egress-only IGW, TGW, and Cloud WAN routing remain forbidden.
Gateway endpoint routes target AWS services privately and do not create general
network egress. This aligns the role with AWS/community `intra` semantics without
weakening its public-connectivity boundary.

Injected route tables extend that boundary to pre-existing state. For an isolated
group, the module reads a plan-known physical ID with `data.aws_route_table` and
accepts only local and gateway-endpoint routes. A computed ID cannot form a stable
inspection instance during planning and therefore fails closed. The sole bypass is
`isolated_accepts_uninspected_route_table = true`; this dangerous opt-in is valid
only for an isolated group with `manage_route_table = false` and transfers
responsibility for all unmanaged routes to the caller.

### 3.3.7 Cloud WAN accepter ownership is independent

The accepter collection uses the constant key `"vpc"` whenever the three plan-known
flags `require_acceptance`, `accept_attachment`, and `create_accepter` are true.
Its `attachment_id` is the effective created or injected attachment ID, so attachment
ownership and accepter ownership form an explicit 2×2 create/inject matrix.

### 3.3.6 ADR-R9-A2 — explicit CIDRs are keyed by Availability Zone

**Decision:** `ipv4.cidrs_by_az` and `ipv6.cidrs_by_az` are maps whose keys must
exactly equal the configured AZ names. The unpublished positional `cidrs` lists are
removed without an adapter. Subnet state remains `<group>/<az>`, while CIDR lookup
uses the same AZ key instead of a list index.

**Rationale:** inserting or reordering an AZ can no longer assign a different
ForceNew CIDR to an existing subnet address. Migration reads each current subnet
CIDR from state and records it under that subnet's AZ. Map declaration order has no
semantic effect; missing and extra AZ keys fail at plan time with the group name.

### 3.3.5 ADR-R8-3 — NACL rule number is state identity

**Decision:** each subnet group may optionally create or inject one Network ACL.
Rules are direction-specific maps whose keys are canonical AWS rule numbers; the
resource address is `<group>/<ingress|egress>/<rule-number>`, and subnet association
addresses remain `<group>/<az>`. Reordering source declarations therefore produces
no positional churn. Inject mode owns neither ACL identity nor tags, but does own
explicitly declared rules and associations against that ID.

The absent block is semantically significant: no ACL, rule, or association resource
is planned, preserving AWS default-NACL behavior. The contract validates ownership,
rule-number range, protocol, action, exactly one address family, port ordering, and
ICMP fields before apply. NACLs remain an opt-in defense-in-depth control because
their stateless reverse-path complexity is inappropriate as a default.

### 3.3.4 ADR-R8-2 — explicit service plus stable endpoint key

**Decision:** `gateway_endpoints` is a map keyed by caller identity; each value has
`service = "s3" | "dynamodb"`, create-or-inject fields, optional JSON policy, and
Name/tags. Although keys conventionally match services, keeping `service` explicit
allows a plan-time duplicate-service validation that an object with fixed `s3` and
`dynamodb` attributes could never exercise. Exactly one endpoint per service is
allowed.

Route-table associations are separate resources keyed
`<group>/<az-or-injected>/gateway-endpoint/<service>`. Routing intent remains with
the subnet group, and an injected shared route table receives only one association.
This avoids positional churn and lets endpoint IDs be computed. Gateway endpoint
routes bypass NAT processing; S3/DynamoDB traffic therefore avoids NAT per-GB fees.

### 3.3.9 Default VPC resource IDs are observation, not ownership

Tier 1 always exposes scalar IDs for the default security group, default NACL,
default route table, and current main route table. Created VPCs use computed
`aws_vpc` attributes; injected VPCs use scoped lookups. These observations do not
instantiate any `aws_default_*` resource. `default_resources` remains the sole,
false-by-default lifecycle adoption selector.

### 3.3.3 ADR-R8-1 — default resources are adopted only by explicit opt-in

**Decision:** expose independent `manage_security_group`, `manage_network_acl`, and
`manage_route_table` booleans, all defaulting to false. The module uses provider
`aws_default_*` resources, which adopt AWS-created VPC defaults by ID. Managed
security groups have no rules; managed default NACLs have no allow entries; managed
default route tables retain only the implicit local route and no propagation.

**Rationale:** CIS 4.3 favors an empty default security group, but automatic
adoption would violate the v4 migration zero-diff contract and could disconnect
live workloads. Explicit opt-in makes the destructive rule/route reconciliation
reviewable. One `{vpc}`/`{resource}` name format and stable `"default"` resource
keys follow the module naming/state rules without pretending these objects are
created by the module.

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

### 3.5 CIDR Calculation Algorithm

**Deterministic allocation with two-tier pinning:**

1. **Fixed AZ stride:** every calculated group reserves six subnet positions,
   matching the contract's maximum AZ count. Adding an AZ consumes the next
   reserved position and never changes existing AZ CIDRs.
2. **Pinned groups** (`cidr_index` set): the index selects an absolute group slot
   at that netmask. Pins are allocated first and never shift when other groups or
   AZs are added/removed. Absolute pinned ranges that overlap across different
   netmasks are rejected at plan time.
3. **Unpinned groups** (`cidr_index` null): groups pack after all pinned ranges,
   sorted by netmask ascending (largest subnet first) and then group key. Mixed
   netmasks share one /28-normalized address space and cannot overlap.

Primary IPv4 and every caller-keyed secondary IPv4 association are independent
allocation domains. `ipv4.secondary_cidr_key` therefore selects the actual parent
for calculated CIDRs, not only a dependency. Equal pins may be reused under
different parents. Explicit IPv4 and IPv6 CIDRs must be contained in their selected
parent; unknown provider-derived parents defer this precondition to apply before
subnet creation. A failed or overflowing `cidrsubnet` calculation yields no CIDR
and fails a subnet resource precondition; it must never fall back to the parent
CIDR.

**Stability guarantees:**
- Pinned groups: existing CIDRs never shift; conflicting absolute pins fail early.
- Unpinned groups: may shift if a group that sorts before them is added/removed.
- AZ addition: only the newly selected reserved slot is materialized per group.

**IPv6 allocation:** `addressing.secondary` supports N caller-keyed IPv6
associations. Each entry selects Amazon-provided `/56`, IPv6 IPAM/static addressing
(`/44` through `/60` in `/4` increments), or an injected association. Every IPv6
subnet names its parent with `secondary_cidr_key` and accepts explicit AZ-keyed
`/64`s, subnet IPAM `/64`s, or deterministic `/64`s when `auto_assign=true`.
Six-AZ reservations, pinning, and unpinned packing are independent per parent, so
the same `cidr_index` can be reused under different associations. `native_only=true`
omits IPv4 and still requires a real selected IPv6 source.

**Production recommendation:** use explicit `cidrs_by_az` for the strongest immutable
allocation contract, `cidr_index` for stable calculated six-AZ reservations, and
bare `netmask`/`auto_assign` only where shifts after group mutations are acceptable.

### 3.5.1 Tier 2 injected-VPC warning disposition

The deprecated `vpc_attributes` alias intentionally remains the complete v4/provider
object through v5. Projecting it would remove attributes and break the migration
contract. AWS provider 6.59 emits `ipv6_association_id` deprecation warnings when an
injected `data.aws_vpc` object is evaluated; this known warning is deferred to the
v6 removal of Tier 2. Tier 1 consumers use scalar outputs and are not coupled to that
shape, but Terraform still evaluates root outputs. CI records this exact warning and
must treat any different warning as new debt.

### 3.6 Outputs — 3 Tiers

#### Tier 1: stable handles (semver-protected)

Tier 1 names, value types, and existing collection keys do not change without a
major release. Minor releases may add outputs or additive map keys.

- VPC/AZ: `vpc_id`, `vpc_arn`, `vpc_cidr_block`, `vpc_ipv6_cidr_blocks`, `secondary_ipv4_cidr_association_ids`, `secondary_ipv6_cidr_association_ids`, deprecated singular `vpc_ipv6_cidr_block`, `azs`.
- Subnet IDs: `subnet_ids_by_group`, `subnet_ids_by_group_by_az`,
  `subnet_ids_by_semantic_role`, `subnet_ids_by_semantic_role_by_az`.
- Subnet CIDRs/ARNs: `subnet_cidrs_by_group`,
  `subnet_cidrs_by_group_by_az`, `subnet_ipv6_cidrs_by_group_by_az`,
  `subnet_cidrs_by_semantic_role`, `subnet_cidrs_by_semantic_role_by_az`,
  `subnet_arns_by_group_by_az`.
- Route tables: `route_table_ids_by_group`,
  `route_table_ids_by_group_by_az`, `route_table_ids_by_semantic_role`,
  `route_table_ids_by_semantic_role_by_az`.
- NAT/gateways: `nat_gateway_ids`, `nat_public_ips`, `nat_private_ips`,
  `nat_eip_allocation_ids`, `internet_gateway_id`, `egress_only_igw_id`,
  and `secondary_cidr_association_ids`.
- Attachments/logging/Lattice: `transit_gateway_attachment_id`,
  `core_network_attachment_id`, `core_network_attachment_accepter_id`,
  `flow_log_ids`, `flow_log_destination_arns`, `flow_log_role_arns`,
  and `vpc_lattice_service_network_association_id`.
- D6: `vpc_block_public_access_options_id`,
  `vpc_block_public_access_exclusion_ids`, and `dhcp_options_id`.

Per-role/per-AZ values are lists because v5 permits multiple groups sharing one
semantic role. Consumers such as hubandspoke and cloudwan can select group or
semantic-role handles without parsing v4 composite keys or querying subnets again.

#### Tier 2: deprecated v4-compatible aliases (present in v5, removed in v6)

The following reproduce the exact v4 output name and outer shape:

- `vpc_attributes`, `azs`, `transit_gateway_attachment_id`,
  `core_network_attachment`;
- `private_subnet_attributes_by_az` with `<group>/<az>` keys;
- `public_subnet_attributes_by_az`, `tgw_subnet_attributes_by_az`, and
  `core_network_subnet_attributes_by_az` with AZ keys;
- `rt_attributes_by_type_by_az` with the exact `private`, `public`,
  `transit_gateway`, and `core_network` outer keys;
- `nat_gateway_attributes_by_az`, `natgw_id_per_az`, `internet_gateway`,
  `egress_only_internet_gateway`;
- `vpc_lattice_service_network_association`, `flow_log_attributes`.

Full-object attributes remain provider-controlled. Exact reserved-group aliases
require migrated groups to retain the v4 keys `public`, `transit_gateway`, and
`core_network`; the migrated single Flow Log uses key `default`.

The pre-publication aliases `subnet_ids_by_role`, `subnet_ids_by_role_by_az`, and
`subnet_cidrs_by_role_by_az` also remain deprecated through v5.

#### Tier 3: internal-resource escape hatch (no semver guarantee)

`resources` exposes created/existing VPC collections, subnets, route tables and
associations, gateways, EIPs/NAT Gateways, attachments/accepter, Flow Logs and
CloudWatch/IAM resources, Lattice associations, secondary CIDR associations,
BPA/DHCP resources, injected handles, and every route collection. Provider
objects are complete except `flow_log_roles`, whose entries are projected to
`arn`, `id`, `name`, and `unique_id` so the output does not evaluate the AWS
provider's deprecated `inline_policy` attribute. Its shape may change in any
release.

### 3.7 Cross-Variable Invariants (enforced via preconditions)

These cannot be expressed as variable validations (Terraform limitation: no cross-var refs).
They are enforced as `lifecycle.precondition` on the relevant resource, which means they
fire at plan time when values are known. With `availability_zones.count`, the selected
AZ names come from `data.aws_availability_zones`; preconditions that depend on that set
are unknown during the initial plan and Terraform defers them to apply time. Production
callers should use explicit `names` for stable AZ identity and plan-time diagnostics.

1. **cidrs length == AZ count**: IPv4 and IPv6 cardinality resources.
2. **count <= discovered AZs**: `terraform_data.availability_zone_count_validation`.
3. **nat_gateway.az ∈ resolved AZs**: `terraform_data.nat_gateway_az_validation`.
4. **VPC/subnet IPv6 sources exist and are exclusive**: IPv6 addressing preconditions.
5. **Subnet addressing exists**: `aws_subnet.main` precondition.
6. **Injected IDs accompany explicit ownership flags**: variable/resource preconditions.
7. **Secondary selector exists before subnet creation**: stable-key validation plus
   subnet dependency on created associations.
8. **isolated has no Internet/transit routing**: IGW, NAT/NAT64, EIGW, TGW, and
   Cloud WAN are rejected; S3/DynamoDB gateway endpoint routes are allowed.

### 3.8 Provider Floor

Required AWS provider: `>= 6.29`.

The limiting feature is subnet IPAM: the v5 implementation sets
`ipv4_ipam_pool_id` and `ipv4_netmask_length` on `aws_subnet`, including null in
non-IPAM paths, and those schema arguments require AWS provider 6.29. The other
Phase 3 additions have lower floors: `private_dns_enabled` on the VPC Lattice
association requires 6.27, while TGW `security_group_referencing_support` requires
5.69. A consumer locked to provider 5.x can satisfy neither the published schema
nor validate the complete module, so v5 intentionally raises the major floor.

### 3.9 Isolated Role Semantics

`isolated` means no route to Internet or transit connectivity. It rejects IGW,
NAT/NAT64, EIGW, TGW, and Cloud WAN, while allowing S3 and DynamoDB gateway
endpoints because those are private service routes and do not provide Internet
reachability. Use `role = "private"` for broader selective routing.

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

`private_dns_enabled` defaults to false because changing private DNS replaces the
association by provider design. When enabled, the typed `dns_options` contract
defaults `private_dns_preference` to `VERIFIED_DOMAINS_ONLY`, matching the value
returned by AWS. The resource always sends that preference: AWS also returns a
computed `private_dns_specified_domains = ["*"]` sentinel, and provider 6.59 marks
the whole block ForceNew, so omitting `dns_options` would plan a destructive
replace after every successful apply. Specified domains are accepted only for
`VERIFIED_DOMAINS_AND_SPECIFIED_DOMAINS` and `SPECIFIED_DOMAINS_ONLY`, with the AWS
1-10 item and 255-character limits. `ignore_changes` was rejected because it would
hide deliberate DNS preference changes as well as service drift. Security groups
are a set, because ordering is meaningless, and the contract rejects more than the
AWS quota of five.

#### ADR-F3-4 — Flow Logs validation boundary

The contract validates supported CloudWatch retention periods, non-empty optional
ARNs, mandatory external destination ARNs for S3/Firehose, and Flow Log Name
formats. `flow_logs[*].name_format` defaults to `{vpc}-{key}-flow-logs`;
`cloudwatch_options.name_format = null` inherits it, while `""` explicitly omits
`Name`. This independent override is necessary because v4 tagged the Flow Log with
`vpc.name` but left its generated CloudWatch group without `Name`. It does not infer
cross-account ownership from an ARN or attempt to prove IAM permissions at plan
time; those are runtime/account-policy concerns. `deliver_cross_account_role_arn`
is accepted as an explicit non-empty ARN and remains caller-owned.

### 3.10.1 Remediation batch 1 ADRs

#### ADR-R1-1 — Keep `availability_zones.count`, but make it exact

**Decision:** retain development-only count mode. Sort eligible data-source names,
then select exactly `slice(0, count)`; fail if discovery returns fewer names.
Explicit `names` remain the production contract because a future AZ can alter the
sorted prefix. This follows the final technical audit recommendation rather than
removing a documented mode.

#### ADR-R1-2 — Ownership flags, never ID nullness, decide cardinality

**Decision:** add plan-known selectors (`vpc.create`, `vpc.igw_create`,
`vpc.eigw_create`, subnet/route-table ownership, `nat_gateway.create`,
attachment ownership, Flow Log create flags, and `vpc_lattice.enabled`). IDs/ARNs are values only and may be computed upstream.
This is a deliberate pre-release contract correction: inferring ownership from
`id == null` makes Terraform unable to know count/for_each during the first plan.

#### ADR-R1-3 — One deterministic IPv6 engine

**Decision:** derive automatic subnet `/64`s independently from each selected
secondary IPv6 parent with the same six-AZ stride and caller pinning model as IPv4.
Explicit `/64` and subnet IPAM stay first-class alternatives. `auto_assign` enables
address assignment and selects the derived path only when neither explicit CIDRs
nor IPAM is configured.

#### ADR-R1-4 — Resolved routing is authoritative

**Decision:** public role supplies the default `internet_gateway=true`, but an
explicit false suppresses the IGW and default route. A public NAT created by the
module still requires an IGW. `isolated` rejects DNS64 because managed NAT64 is
egress routing, not an addressing-only feature.

### 3.10.2 Remediation batch 2 ADRs

#### ADR-R2-1 — Secondary CIDR identity and dependency

**Decision:** `addressing.secondary` is a stable-keyed map whose entries are a
closed union containing exactly one `ipv4` or `ipv6` sub-object. The family object
selects create or inject mode. Subnets reference the matching family entry by
`secondary_cidr_key` and wait for created associations, closing #146/#142 without
targeted applies.

#### ADR-R2-2 — D6 is in scope

**Decision:** implement VPC Block Public Access and DHCP options rather than
silently narrowing D6. BPA options/exclusions and DHCP options publish stable IDs
and support explicit create-or-inject ownership.

#### ADR-R2-3 — Create-or-inject is universal for managed boundaries

**Decision:** EIGW, subnets, TGW/Cloud WAN attachments and accepter, Flow Logs,
Lattice, and secondary associations all use plan-known ownership selectors. S3
and Firehose remain caller-owned data destinations under ADR-F3-1.

### 3.10.3 Remediation batch 4 ADRs

#### ADR-R4-1 — Complete Name formats, separate from state identity

**Decision:** use complete format strings rather than a second family of fixed
`name` fields. Subnet `name_format` supports `{vpc}`, `{group}`, and `{az}`;
`route_table_name_format` inherits it by default. NAT/EIP use the same placeholders
with `{group}` bound to the selected host group's display prefix. IGW/EIGW accept
`{vpc}`. Defaults retain native v5 names, while migration can reproduce v4 exactly
with `{group}-{az}`, `nat-{group}-{az}`, `{vpc}-igw`, and `{vpc}`.

**Rationale:** one format covers one or many AZs without duplicate per-AZ maps,
preserves caller-owned state keys, and still permits a fully literal Name. Route
tables inherit subnet naming because v4 deliberately named both alike, but expose
an independent override for consumers that distinguish them.

#### ADR-R4-2 — Explicit tag layers; no drift suppression

**Decision:** all taggable resources merge provider defaults implicitly and module
layers explicitly as provider < global < group/resource < Name. NAT/EIP inherit the
host subnet-group tags; IGW/EIGW expose boundary-specific tag maps. Do not add
`ignore_changes` for `tags`/`tags_all`; provider-default changes are actionable
configuration, not perpetual drift.

### 3.10.4 ADR-R6 — Regional NAT is a first-class public-egress mode

**Decision:** add `nat_gateway.mode = "regional"` as one VPC-level
`aws_nat_gateway` with `availability_mode = "regional"`, `vpc_id`, no `subnet_id`,
and public connectivity. Route tables in every configured AZ retain their stable
addresses and target the same physical NAT ID. `nat_gateway_ids` preserves its
`map(az, id)` shape by repeating that ID.

`eip.mode = "create"` selects AWS automatic Regional NAT IP/AZ management and
creates no child `aws_eip`. `existing` and `byoip_pool` select provider manual mode
with one `availability_zone_address` block per configured AZ; BYOIP creates one
pool-backed EIP per AZ. The provider's block uses plural `allocation_ids`, not
`allocation_id`. Provider 6.29 (the module floor) already contains all required
schema fields.

**Rationale:** AWS recommends Regional NAT for public-connectivity use cases. It
removes public host subnets, owns an IGW-routed managed route table, follows ENI
presence with zonal affinity, and scales to 32 addresses per AZ. The value is
operational, not lower hourly cost: billing remains per active AZ. Expansion can
take up to 60 minutes and use cross-AZ forwarding in the interim. Regional NAT
cannot provide private connectivity, so private NAT remains zonal.

**Compatibility:** `az` and `subnet_group` are invalid in regional mode. Existing
zonal modes and resource keys are unchanged. Regional public/allocation outputs use
`<az>/<allocation-id>` keys to retain every address without changing their
`map(string)` type; a new grouped address output exposes complete records.

### 3.11 Import and adoption

Existing resources are adopted declaratively by setting the boundary-specific
`create=false` selector and supplying its ID. The module then omits the managed
resource while preserving the same Tier 1 handle. This applies to EIGW, subnets,
secondary associations, TGW/Cloud WAN attachments and accepter, Flow Logs, and
Lattice. Import remains appropriate only when transferring lifecycle ownership
into a `create=true` resource address during migration.

---

## 4. Migration Path v4 → v5

The normative mapping and state procedure is [v5-migration.md](v5-migration.md).
The validateable skeleton under `v5/examples/migration-from-v4` contains a
63-block feature union, not a required per-deployment count. The representative
migration fixture selected 26 applicable sources and omitted 37 absent-feature
blocks. The v4 CloudWatch log group is intentionally excluded from moved blocks:
ADR-F4-1 configures the generated physical name and performs three declarative
`removed { destroy=false }` forgets plus one log-group `import` in the same
zero-destroy normal plan that serves as the acceptance gate. Static moved addresses are otherwise intentional:
Terraform does not permit variables or wildcards in moved addresses, so callers
substitute their actual AZs, private group keys, route destinations, and optional
resources.

## 5. Open Questions (Resolved)

1. ~~Should `isolated` be a distinct role?~~ → **YES.** Kept for validation guard value.
2. ~~Multiple public groups?~~ → **YES.** Singleton removed.
3. ~~Generator script for moved blocks?~~ → Generator approach kept (dynamic `moved` experimental).
4. ~~NAT top-level vs nested?~~ → **Top-level confirmed** (VPC-wide concern).

## 6. Future work / deferred scope

### Frozen structural reservations

These shapes are naming/compatibility commitments, not accepted no-op inputs in
5.0:

```text
nat_gateways = map(object({
  az_keys = set(string)
}))

availability_zones = {
  ids = list(string)
}

addressing.secondary = {
  key = {
    ipv6 = {
      network_border_group = optional(string)
    }
  }
}

subnets = {
  group = {
    az_keys = set(string)
    routing = {
      nat_gateway_key = optional(string)
    }
  }
}
```

`subnets[*].routing.nat_gateway_key` is the reserved selector for a future
caller-keyed NAT domain. `addressing.secondary[*].ipv6.network_border_group` is
the only reserved placement for IPv6 network-border-group selection. `az_keys` is
the single placement dimension for Regional Availability Zones, Local Zones, and
Wavelength Zones; no parallel `zones` axis will be introduced.

The singular NAT handle remains a future compatibility adapter. Plural IPv6
associations and per-subnet parent selection are implemented;
`vpc_ipv6_cidr_block` is only a deprecated first-sorted-key adapter. BYOIPv6 and
network-border-group ownership remain deferred.

The additive reservations from #176/#178 use these exact defaults and omission
semantics: `core_network_options.dns_support = optional(bool, false)`,
`security_group_referencing_support = optional(bool, true)`, and
`routing_policy_label = optional(string)` with `null` meaning no label. Public
IPAM EIPs use `nat_gateway.eip.mode = "ipam_pool"` plus
`ipam_pool_id = optional(string)`; that mode requires a non-empty ID and excludes
`public_ipv4_pool` and `allocation_ids`.

- **Phase 2**: Route table injection via `subnets[*].route_table_id` — ✅ DONE
- **Phase 2**: NAT Gateway injection via `existing_ids` — ✅ DONE
- **Phase 2**: IGW injection via `vpc.igw_create=false` + `vpc.igw_id` — ✅ DONE
- **Phase 2**: EIGW creation + routing — ✅ DONE
- **Phase 2**: Private NAT (connectivity_type) — ✅ DONE
- **Phase 2**: DNS64/NAT64 support — ✅ DONE; functional IPv6 regression coverage added in `db758f7`
- **Phase 2**: Route tables co-located per group/az — ✅ DONE
- **Phase 4**: Tiered outputs and v4 migration guide/example — ✅ DONE (`9a4bb9c`)
- **Phase 5**: Native plan-only contract tests, stateful moved fixture, examples, and generated docs — ✅ DONE (`a5fb279`, `2db15d7`)
- **Remediation 1**: IPv6/AZ count/computed-ID selectors/routing coherence — ✅ DONE (`db758f7`, `0a1f424`)
- **Remediation 2**: D6, stable secondary IPAM, boundary injection, TFLint/CI — ✅ DONE (`3f96aba`, `606fc47`)
- **Post-v5**: `stable_key` alternative to map-key-as-state-identity — evaluate need post-launch
