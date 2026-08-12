# Gate Fase 1 — Findings Resolution (R1 + R2)

> **Date:** 2026-08-12
> **Gate status:** ✅ CLOSED — All Critical and High findings resolved or documented.
> **Builder:** Agent (explore/v5-typed-contract)
> **Reviewers:** R1 (Primitives/Design), R2 (Terraform Quality)

---

## Critical Findings

| ID | Finding | Resolution | File(s) | Status |
|---|---|---|---|---|
| R1-C1 | Singleton constraint blocks N public groups | Removed `<= 1` validation for `public` role. TGW/CWAN kept singleton with AWS API rationale documented in validation error + comments. | `v5/variables.tf` | ✅ Closed |
| R1-C2 | netmask CIDR posicional sin pinning | Two-tier allocation algorithm: pinned (`cidr_index`) + unpinned (alphabetical). Full stability proof in `locals.tf` header comments. Documentation in RFC §3.5. | `v5/locals.tf`, `v5/variables.tf`, `docs/rfc/v5-contract.md` | ✅ Closed |
| R1-C3 | routing.transit_gateway single-string → can't express multiple routes | Changed to `list(string)` for `transit_gateway`, `transit_gateway_ipv6`, `core_network`, `core_network_ipv6`. Hub example demonstrates multi-route. | `v5/variables.tf`, `v5/examples/hub/main.tf` | ✅ Closed |
| R2-C1 | Provider floor >= 5.0 too low (security_group_referencing needs >= 5.69) | Floor raised to `>= 5.69` in `versions` block + all examples. Documented in RFC §3.8. | `v5/variables.tf`, `v5/examples/*/main.tf` | ✅ Closed |
| R2-C2 | No validation: cidrs length vs AZ count | `terraform_data.cidrs_az_count_validation` precondition enforces at plan/apply time. Error message identifies subnet group and counts. | `v5/main.tf` | ✅ Closed |
| R2-C3 | No validation: nat_gateway.az ∉ AZs | `terraform_data.nat_gateway_az_validation` precondition enforces at plan/apply. Error message names the invalid AZ and lists valid ones. | `v5/main.tf` | ✅ Closed |

## High Findings

| ID | Finding | Resolution | File(s) | Status |
|---|---|---|---|---|
| R1-H1 | Rename key = destroy, no escape hatch | Documented prominently in variable description and RFC §3.2. Keys described as immutable. `name_prefix` for cosmetic decoupling. `stable_key` deferred to post-v5 evaluation (RFC §6). | `v5/variables.tf`, `docs/rfc/v5-contract.md` | ✅ Closed (documented) |
| R1-H2 | Create-or-inject incomplete (IGW, NAT GW) | Added `vpc.igw_id` (IGW injection), `nat_gateway.existing_ids` (NAT GW injection). IGW resource with create-or-inject logic in main.tf. Route table injection deferred to Phase 2 (complexity, RFC §6). | `v5/variables.tf`, `v5/locals.tf`, `v5/main.tf`, `v5/outputs.tf` | ✅ Closed (Phase 1 scope) |
| R1-H3 | Outputs by group name, not by semantic role | Added `subnet_ids_by_semantic_role` and `subnet_ids_by_semantic_role_by_az` as Tier 1 outputs. Old outputs renamed to `*_by_group` with deprecated aliases kept for Tier 2. | `v5/outputs.tf` | ✅ Closed |
| R1-H4 | availability_zones.count depends on data source ordering | Documented as DEVELOPMENT ONLY in variable description, RFC, and locals.tf. Production users directed to use explicit `names`. | `v5/variables.tf`, `docs/rfc/v5-contract.md` | ✅ Closed (documented) |
| R2-H1 | Unknown values skip variable validations silently | Cross-variable invariants enforced as `precondition` on resources (`terraform_data` for standalone, `lifecycle` on `aws_subnet.main`). These fire at apply time when values become known. Documented in RFC §3.7. | `v5/main.tf`, `docs/rfc/v5-contract.md` | ✅ Closed |
| R2-H2 | allocation_ids default `{}` misleading | Changed to `optional(map(string))` (nullable, default null). Validation updated to check `!= null` for existing mode. | `v5/variables.tf` | ✅ Closed |
| R2-H3 | routing.internet_gateway no explicit default | Documented: null = auto (true for public, false otherwise). Resolved in `locals.tf` via `coalesce()`. RFC §3.2 updated. | `v5/variables.tf`, `v5/locals.tf` | ✅ Closed |
| R2-H4 | RFC ↔ code divergence (security_group_referencing) | RFC §3.2 now includes `security_group_referencing` in `transit_gateway_options`. Provider floor aligned at >= 5.69 in both. | `docs/rfc/v5-contract.md` | ✅ Closed |

## Medium Findings (addressed opportunistically)

| ID | Finding | Resolution | Status |
|---|---|---|---|
| R1-M1 | Isolated validation doesn't prohibit TGW/CWAN routing | Extended validation to block ALL routing fields for isolated role. | ✅ Closed |
| R2-M1 | No netmask range validation (accepts 0, 100, -1) | Added `>= 16 && <= 28` validation. | ✅ Closed |
| R1-M2 | isolated vs private undocumented | RFC §3.9 documents: "isolated = private with routing guard". | ✅ Closed |

## Deferred (out of Phase 1 scope)

| ID | Finding | Target Phase | Notes |
|---|---|---|---|
| R1-H2 (partial) | Route table injection | Phase 2 | High complexity, less frequent use case |
| R1-H2 (partial) | EIGW injection | Phase 2 | Follows same pattern as IGW |
| R1-H1 (partial) | `stable_key` alternative | Post-v5 evaluation | May not be needed if key immutability is well-documented |
| R2-M2 | addressing.ipv4 allows empty (neither cidr nor IPAM) | Phase 1 backlog | Low risk, existing precondition catches at VPC creation |
| R2-M3 | ipam_pool_id without netmask_length not validated at subnet level | Backlog | Already validated at variable level |
| R2-M4 | flow_logs.retention_days without range | Phase 3 (flow logs) | Out of scope for subnet engine |
| R2-M5 | Output naming confusion (by_role vs by_group) | Phase 1 | ✅ Fixed: renamed + deprecated aliases |

---

## Contract Breaking Changes from Gate 1

| Change | Impact on Examples | Adaptation |
|---|---|---|
| `routing.transit_gateway`: `string` → `list(string)` | Hub example used `transit_gateway = "10.0.0.0/8"` | Changed to `transit_gateway = ["10.0.0.0/8", "172.16.0.0/12"]` |
| Provider floor: `>= 5.0` → `>= 5.69` | All examples declared `>= 5.0` | Updated to `>= 5.69` |
| `subnet_ids_by_role` → deprecated | Examples referenced `module.vpc.subnet_ids_by_role` | Changed to `subnet_ids_by_group` + added `subnet_ids_by_semantic_role` |
| `subnet_ids_by_role_by_az` → deprecated | Enterprise/hub examples | Changed to `subnet_ids_by_group_by_az` |
| Public singleton removed | No breakage (relaxation) | Hub example now shows 2 public groups |
| `allocation_ids` default `{}` → `null` | Hub example explicit — no impact | No change needed |

---

## Validation Results

```
v5/                     → terraform validate: ✅ Success
v5/examples/basic/      → terraform validate: ✅ Success
v5/examples/enterprise/ → terraform validate: ✅ Success
v5/examples/hub/        → terraform validate: ✅ Success
```
