# Migration from v4

This is a state-migration skeleton, not a deployable network template. Follow the complete runbook and ADR in `../../../docs/rfc/v5-migration.md`.

1. With v4 still configured, back up state, upgrade Terraform/AWS provider separately, and reach a clean **normal** plan.
2. Copy the exact observed order of `module.vpc.azs` into `availability_zones.names`; align every explicit CIDR list to that order. Keep the v4 group keys `public`, `transit_gateway`, `core_network`, and every private key unchanged.
3. Capture the physical v4 CloudWatch log-group name and IAM role `name_prefix` with `terraform state show`. Put them in `flow_logs.default.cloudwatch_options.name` and `flow_logs.default.role_name_prefix`.
4. Copy this example's active `moved.tf` to the caller root, substitute real AZs/groups/destinations, and remove blocks whose source is absent. The log group intentionally has no moved block: remove its old state address and import the same physical group at `module.vpc.aws_cloudwatch_log_group.flow_logs["default"]`.
5. Run a complete `terraform plan` (never `-refresh-only` as the migration gate). Require zero replacements and compare every action with the allowlist in the RFC.
6. Create the v5 inline Flow Logs role policy with the documented targeted first apply, verify delivery, then run and apply a new complete plan that retires the old managed attachment/policy.
7. Verify preserved physical IDs, no residual v4 addresses, active Flow Logs with new events, and a final normal plan with detailed exit code 0.

The active `moved.tf` contains 63 moves for two AZs and representative `public`, `app`, `transit_gateway`, and `core_network` groups. It preserves the Flow Log and IAM role addresses, but deliberately excludes the replacement-prone v4 `name_prefix` -> v5 `name` log-group move.
