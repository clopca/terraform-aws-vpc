# Gate Fase 2 — Findings Resolution (R1 + R2)

> **Date:** 2026-08-12
> **Gate status:** ✅ CLOSED — no Critical or High findings remain open.
> **Builder:** Agent (`explore/v5-typed-contract`)
> **Reviewers:** R1 (Primitives/Design), R2 (Terraform Quality)
> **Resolution commit:** `97c89ee`

## Critical and High Findings

| Finding | Resolution | Commit | Status |
|---|---|---|---|
| R1#1 / R2#1 — TGW and Cloud WAN route keys use positional list indexes | Replaced positional suffixes with normalized destination CIDRs for IPv4 and IPv6 TGW/CWAN routes. Reordering destination lists now produces no route resource churn; adding or removing a destination affects only that route. | `97c89ee` | ✅ Closed |
| R1#2 — Private NAT placement selected the first private group implicitly | Added `nat_gateway.subnet_group`, documented the null fallback, updated production examples to pin placement, and added preconditions that require the selected group to exist and have a compatible `public`/`private` role. Missing compatible groups now fail with a contract error instead of an AWS API error. | `97c89ee` | ✅ Closed |
| R1#3 — Route tables lacked create-or-inject support | Added `subnets.<group>.route_table_id`. Injected groups skip route-table creation, associate every group subnet with the existing table, expose the injected ID through stable outputs, and add declared managed routes to that table once. Documented route ownership/conflict behavior and rejected shared injected tables with per-AZ NAT routing. | `97c89ee` | ✅ Closed |
| R2#2 — Examples did not exercise NAT `existing_ids`, TGW IPv6, or Cloud WAN routes from non-attachment subnets | Basic now injects an existing NAT Gateway and route table. Hub now exercises `transit_gateway_ipv6` plus IPv4/IPv6 `core_network` routes from the `firewall` group. Enterprise and hub pin NAT placement explicitly. | `97c89ee` | ✅ Closed |
| R2#3 — Apply-time deferral with `availability_zones.count` was undocumented | The variable description and RFC now state that AZ-dependent preconditions are unknown during the initial plan and deferred by Terraform to apply. Explicit `names` remains the production recommendation. | `97c89ee` | ✅ Closed |

## Functional and Opportunistic Medium Findings

| Finding | Resolution | Commit | Status |
|---|---|---|---|
| R1#4 — `dns64 = true` enabled synthesis without the NAT64 route | Added managed `64:ff9b::/96 -> NAT Gateway` routes and a precondition that rejects DNS64 when NAT is disabled. The same route-table create-or-inject semantics apply. | `97c89ee` | ✅ Closed |
| R2#4 — Private NAT without a compatible subnet produced an opaque provider error | Covered by the new NAT host-group existence and role preconditions. | `97c89ee` | ✅ Closed |
| R1#5 — Adding destination types requires edits in variables, locals, and resources | No correctness or compatibility defect. Generic `additional_routes` remains a post-v5 extensibility option; typed route fields remain the v5 contract. | N/A | ⏭ Deferred (non-blocking) |
| R2#5 — TGW destination lists lack protocol/CIDR validation | Provider validation remains the current behavior. Strong IPv4/IPv6 validation is backlog work and does not affect route identity or gate safety. | N/A | ⏭ Deferred (non-blocking) |
| R2#6 — Private NAT retains an unnecessary IGW dependency edge | Confirmed harmless because the referenced resource set is empty when no IGW is created. No functional change required. | N/A | ✅ Accepted |
| R2#7 / R2#8 — Association ordering and count-mode CIDR check timing | Terraform dependency graph is correct; count-mode apply deferral is now explicitly documented. | `97c89ee` | ✅ Closed |

## Contract Decisions

### Existing route table ownership

`route_table_id` is one shared existing table per subnet group. The module manages
associations and every route declared by that group's `routing` block. Callers are
responsible for avoiding duplicate destinations managed elsewhere. One shared table
cannot select different NAT Gateways by AZ, so NAT/NAT64 with `all_azs` requires the
module-created per-AZ route tables.

### NAT placement default

`nat_gateway.subnet_group = null` selects the first compatible group alphabetically
for backward-compatible convenience. Production configurations should set the field
explicitly; all create-mode production examples now do so.

### Route-key migration

The destination-based route keys intentionally replace unpublished v5 prototype
index keys. Because v5 has not been released, no public migration block is required.
Any state created directly from the prototype branch must move each
`aws_route.{tgw,tgw_ipv6,cwan,cwan_ipv6}` address from its numeric suffix to the
normalized CIDR suffix before applying.

## Validation Results

Executed after the implementation changes and again before recording gate closure:

```text
v5/                     terraform init -backend=false: PASS; terraform validate: PASS
v5/examples/basic/      terraform init -backend=false: PASS; terraform validate: PASS
v5/examples/enterprise/ terraform init -backend=false: PASS; terraform validate: PASS
v5/examples/hub/        terraform init -backend=false: PASS; terraform validate: PASS
terraform fmt -recursive v5: PASS
git diff --check: PASS
```
