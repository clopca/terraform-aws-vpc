# Gate Fase 4 — Findings Resolution (R1 + R2)

> **Date:** 2026-08-12
> **Gate status:** ✅ CLOSED — no Critical or High findings remain open.
> **Builder:** Agent (`explore/v5-typed-contract`)
> **Reviewers:** R1 (Primitives/Compatibility), R2 (Migration/State)
> **Resolution commits:** `9834664`, `724c964`

## Findings

| Finding | Resolution | Commit | Status |
|---|---|---|---|
| R1-H1 — Provider floor documentation mixed 6.29/6.32 | Verified the later correction already present: current contract and build-plan requirements consistently declare AWS provider `>= 6.29`; historical Phase 3 evidence remains explicitly superseded. No duplicate edit was made in this gate round. | `9834664` | ✅ Closed |
| R2-H1(a) — v4 Flow Logs log group `name_prefix` -> v5 `name` would replace despite `moved` | Removed the unsafe log-group moved block. The v5 typed contract now documents and validates exact fixed-name preservation. The runbook captures the generated v4 `name` with `terraform state show`, configures `cloudwatch_options.name`, removes only the old state address, and imports the same physical group at the v5 address. The active fixture now has 63 moves. | `724c964` | ✅ Closed |
| R2-H1(b) — IAM role prefix and managed-policy -> inline-policy ordering | Caller-supplied `role_name_prefix` is no longer silently truncated and is validated at 38 characters. The guide captures the exact v4 `name_prefix`, keeps the role moved block, and guarantees permission order with a targeted inline-policy apply plus delivery verification before the complete apply removes the old attachment/policy. | `724c964` | ✅ Closed |
| R2-H2 — `plan -refresh-only` used as migration gate; no action allowlist/post-check | Replaced it with a provider-only v4 baseline, a saved complete normal v5 plan, explicit zero-replacement/action allowlist (including route residual policy), staged apply, physical-ID/state/Flow Logs verification, and final `plan -detailed-exitcode = 0`. | `724c964` | ✅ Closed |
| R1-M2 — `azs` order observable but undocumented | The guide now obtains `module.vpc.azs` from the v4 configuration/state context and requires copying that exact order into `availability_zones.names` and all explicit CIDR lists. | `724c964` | ✅ Closed |
| R1-M1 — No executable shape assertions for the 15 Tier 2 aliases | Retained in Phase 5 by explicit build-plan scope: Tier 1/Tier 2 shape assertions plus a stateful moved/import migration fixture. | n/a (Phase 5) | ⏭ Scheduled |

## ADR-F4-1 — Flow Logs cutover

The accepted path minimizes surprise by preserving both physical resources:

- **Log group:** exact generated v4 name + state remove/import at the v5 address. A moved block is rejected because provider `name_prefix` and `name` are both ForceNew.
- **IAM role:** moved in place with the exact v4 `name_prefix`; role name and ID remain unchanged.
- **Permissions:** create the v5 inline policy in a targeted first apply, verify the preserved Flow Log is delivering, then remove the old managed attachment/policy in a reviewed complete apply.

Creating a new group or accepting replacement remains an opt-in maintenance-window fallback. It splits continuity; old events remain in the old group only when that group is deliberately retained outside Terraform ownership. It is not the default migration path.

## Complete-plan acceptance criteria

- Zero replacements.
- No create/delete for VPC, subnets, route tables, NAT/EIP, gateways, attachments, CloudWatch log group, or IAM role.
- Re-keyed routes are state-only/no-op when destinations are frozen. A changed destination may delete/create only when enumerated and approved.
- Allowed create: v5 inline Flow Logs role policy.
- Allowed delete after verification: old managed-policy attachment and policy.
- Explicitly reviewed in-place updates only: IAM trust/description/tags, Flow Log settings/tags, and CloudWatch retention/KMS/tags.
- Post-apply: physical IDs preserved, no old Flow Logs module addresses, Flow Log `ACTIVE` with new events, final complete plan exit code 0.

## Validation

Executed with the active 63-block `v5/examples/migration-from-v4/moved.tf`:

```text
v5/                                      init -upgrade -backend=false: PASS; validate: PASS
v5/examples/basic/                       init -upgrade -backend=false: PASS; validate: PASS
v5/examples/enterprise/                  init -upgrade -backend=false: PASS; validate: PASS
v5/examples/hub/                         init -upgrade -backend=false: PASS; validate: PASS
v5/examples/migration-from-v4/           init -upgrade -backend=false: PASS; validate: PASS
terraform fmt -check -recursive v5:      PASS
git diff --check:                        PASS
active moved blocks:                     63
AWS provider selected:                   6.59.0
recorded provider constraint:            >= 6.29.0
```

`terraform validate` proves syntax and address type compatibility, not source presence or plan actions. The complete-plan gate and the Phase 5 stateful fixture own those guarantees.
