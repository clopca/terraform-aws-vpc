# Gate Fase 3 — Findings Resolution (R1 + R2)

> **Date:** 2026-08-12
> **Gate status:** ✅ CLOSED — no Critical or High findings remain open.
> **Builder:** Agent (`explore/v5-typed-contract`)
> **Reviewers:** R1 (Primitives/Design), R2 (Terraform Quality)
> **Resolution commit:** `a9be661`

## Critical and High Findings

| Finding | Resolution | Commit | Status |
|---|---|---|---|
| R2-H1 — TGW/CWAN routes race their attachments/accepter | Added dependency edges only to the four affected route resources: TGW IPv4/IPv6 wait for `aws_ec2_transit_gateway_vpc_attachment.this`; Cloud WAN IPv4/IPv6 wait for `aws_networkmanager_vpc_attachment.this` and the optional accepter. Added a guard that rejects routes while external acceptance is pending. | `a9be661` | ✅ Closed |
| R2-H2 — Declared AWS provider floor `>= 5.69` is false | Moved provider requirements to `v5/versions.tf` and raised module/examples to `>= 6.32`. The limiting schema is `aws_subnet.ipv4_ipam_pool_id` plus `ipv4_netmask_length`; Lattice private DNS needs 6.27 and TGW SG referencing needs 5.69. Local locks were regenerated with `>= 6.32.0` (lock files are ignored by repository policy). | `a9be661` | ✅ Closed |
| R1-H1 / R2-H3 — CloudWatch Flow Logs IAM policy/trust is insufficient | Split publish actions from `logs:DescribeLogGroups`; stream writes remain scoped to the destination while `DescribeLogGroups` uses `Resource = "*"`. Added `aws:SourceAccount` and regional VPC Flow Log `aws:SourceArn` conditions to the role trust policy. | `a9be661` | ✅ Closed |
| R1-H2 — `ignore_changes = [vpc_arn]` hides valid VPC replacement | Removed the lifecycle ignore. The scalar constructed ARN removes unrelated unknown propagation; a real VPC identity change remains ForceNew and correctly replaces the attachment. | `a9be661` | ✅ Closed |
| R1-H3 — Module ownership of S3/Firehose/IAM exceeds the VPC boundary | Removed module-created S3 buckets, Firehose streams, delivery roles, and policies. S3/Firehose now require an external `destination_arn`; CloudWatch remains create-or-inject convenience. ADR-F3-1 records the ownership boundary. | `a9be661` | ✅ Closed |

## Medium Findings and Pre-publication ADRs

| Finding | Resolution / ADR | Commit | Status |
|---|---|---|---|
| R1-M1 — Lattice private DNS default and incomplete DNS contract | Default changed to false and ForceNew behavior documented. Additional DNS preference/domain fields are accepted as future additive work after migration semantics are reviewed (ADR-F3-3). | `a9be661` | ✅ Resolved + ADR |
| R1-M2 — Lattice security groups modeled as ordered list without quota | Changed to `set(string)` and added a maximum-five validation matching the AWS quota. | `a9be661` | ✅ Closed |
| R1-M3 — Created role trust lacks confused-deputy protection | Hardened the retained CloudWatch role with SourceAccount/SourceArn. The Firehose role no longer exists because Firehose is external. | `a9be661` | ✅ Closed |
| R1-M4 — In-module Cloud WAN accepter cannot serve owner-account acceptance | `accept_attachment` now defaults false; true is guarded to same-account Core Networks. Cross-account acceptance is explicitly external and staged before adding routes (ADR-F3-2). | `a9be661` | ✅ Closed |
| R1-M5 — Flow Log validations and stable destination/role outputs are incomplete | Added supported CloudWatch retention validation, non-empty ARN checks, mandatory external S3/Firehose destination ARNs, and Tier 1 `flow_log_destination_arns` / `flow_log_role_arns`. Runtime IAM/cross-account authorization remains caller responsibility (ADR-F3-4). | `a9be661` | ✅ Resolved + ADR |
| R2-M1 — Redundant `ignore_changes` | Same resolution as R1-H2: removed; documentation now distinguishes spurious unknown elimination from correct identity replacement. | `a9be661` | ✅ Closed |
| R2-M2 — Default CloudWatch/Firehose names collide between module instances | Generated CloudWatch log-group names now include the resolved VPC ID. Module-created Firehose naming was removed with external destination ownership. | `a9be661` | ✅ Closed |
| R2-M3 — Core Network ARN and external-acceptance preconditions incomplete | Validate the complete partition-aware Network Manager ARN and matching ID; reject same-module acceptance for a different owner account and reject routes during pending external acceptance. | `a9be661` | ✅ Closed |
| R2-M4 — Tier 3 omits created Flow Log destinations/roles | Tier 3 now exposes created CloudWatch log groups, roles, and role policies. External S3/Firehose resources remain outside module ownership by design. | `a9be661` | ✅ Closed |

## Low Findings

| Finding | Resolution / ADR | Commit | Status |
|---|---|---|---|
| R1-L1 — Import/adoption undocumented | Added import examples for TGW, Cloud WAN, Lattice, and caller-keyed Flow Logs to the RFC. | `a9be661` | ✅ Closed |
| R1-L2 — RFC overstates anti-replace closure | Corrected: scalar ARN construction removes the spurious unknown; actual VPC identity changes still trigger the provider's correct replacement. | `a9be661` | ✅ Closed |
| R2-L1 — Examples do not prove apply-time race behavior | Syntax coverage remains in the three examples. Apply/graph assertions are explicitly retained for Phase 5, where the build plan already owns plan-only and integration tests; the route edges and acceptance guard are present in Phase 3 code. | `a9be661` | ⏭ Accepted for Phase 5 |

## Contract Decisions

### Durable Flow Log destinations

S3 buckets and Firehose delivery streams are injected external resources. Their
retention, KMS, lifecycle, bucket ownership/policy, delivery role, and buffering
belong to dedicated logging infrastructure rather than the VPC module.

### Cloud WAN acceptance

Automatic acceptance is same-account only and opt-in. Cross-account callers apply
the attachment without routes, accept it in the Core Network owner account, then
set `require_acceptance = false` and add routes in a subsequent apply.

### Anti-replace invariant

Cloud WAN derives the ForceNew VPC ARN from partition, region, account, and the
scalar VPC ID. Changes to tags, DNS, secondary CIDRs, or subnet membership do not
change that ARN. Replacing or changing the VPC identity changes the ARN and replaces
the attachment as required.

## Validation Results

Executed after the implementation changes and lock regeneration:

```text
v5/                     terraform init -backend=false: PASS; terraform validate: PASS
v5/examples/basic/      terraform init -backend=false: PASS; terraform validate: PASS
v5/examples/enterprise/ terraform init -backend=false: PASS; terraform validate: PASS
v5/examples/hub/        terraform init -backend=false: PASS; terraform validate: PASS
terraform fmt -check -recursive v5: PASS
git diff --check: PASS
AWS provider selected: 6.58.0; recorded constraint: >= 6.32.0
```

> **Corrección posterior (fase-3 verificación):** el floor real es `>= 6.29` — los argumentos IPAM de `aws_subnet` se publicaron en 6.29, no 6.32. Corregido en módulo, ejemplos y RFC.
