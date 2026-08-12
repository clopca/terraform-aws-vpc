# Migration from v4

This is a state-migration skeleton, not a deployable network template. Follow the complete runbook and ADR in `../../../docs/rfc/v5-migration.md`.

1. With v4 still configured, back up state, upgrade Terraform/AWS provider separately, and reach a clean **normal** plan.
2. Copy the exact observed order of `module.vpc.azs` into `availability_zones.names`; align every explicit CIDR list to that order. Keep the v4 group keys `public`, `transit_gateway`, `core_network`, and every private key unchanged.
3. Copy the v4 Name formulas exactly: `name_format = "{group}-{az}"` on every subnet group, `nat_gateway.name_format = "nat-{group}-{az}"`, `vpc.igw_name_format = "{vpc}-igw"`, and `vpc.eigw_name_format = "{vpc}"`. Copy every v4 `name_prefix` and tag map unchanged.
4. Capture the physical v4 CloudWatch log-group name and IAM role `name_prefix` with `terraform state show`. Put them in `flow_logs.default.cloudwatch_options.name` and `flow_logs.default.role_name_prefix`.
5. Copy this example's active `moved.tf` to the caller root, substitute real AZs/groups/destinations, and remove blocks whose source is absent. The 63 blocks are a feature union, not a target count: the remediation-3 fixture used 26 and omitted 37 absent-feature sources.
6. Materialize those address moves with the saved refresh-only state plan described in the runbook. This is not the migration gate. Then remove the old log-group state address and import the same physical group at `module.vpc.aws_cloudwatch_log_group.flow_logs["default"]`; materializing EIP/NAT moves first prevents evaluation against stale v4 keys.
7. Run a complete normal `terraform plan` (never use refresh-only as the acceptance gate). Require zero replacements and compare every action with the allowlist in the RFC, including the internal `terraform_data` state records.
8. Create the v5 inline Flow Logs role policy with the documented targeted first apply, verify delivery, then run and apply a new complete plan that retires the old managed attachment/policy.
9. Verify preserved physical IDs, no residual v4 addresses, active Flow Logs with new events, and a final normal plan with detailed exit code 0.

The active `moved.tf` contains 63 moves for the union of two-AZ `public`, `app`, `transit_gateway`, `core_network`, routing, attachment, Lattice, NAT/EIP, and Flow Logs features. Keep only sources present in `terraform state list`; repeat the private pattern per real group. It preserves Flow Log and IAM role addresses, but deliberately excludes the replacement-prone v4 `name_prefix` -> v5 `name` log-group move.
