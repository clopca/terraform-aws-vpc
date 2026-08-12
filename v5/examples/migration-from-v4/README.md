# Migration from v4

This example shows the transition pattern, not a deployable network template. Copy the current v4 CIDRs, AZs, route destinations, attachment IDs, and tags from configuration/state before planning v5.

1. Keep the v4 reserved group names `public`, `transit_gateway`, and `core_network`; keep every other v4 subnet map key unchanged.
2. Translate variables using `../../../docs/rfc/v5-migration.md`.
3. Copy `moved.tf.example` to `moved.tf`, remove blocks for resources absent from state, and substitute the real AZs, private groups, and destinations.
4. Run `terraform plan -refresh-only`; it must show address moves and no infrastructure changes.
5. Run a normal plan and resolve every replacement before apply.
6. Migrate downstreams from Tier 2 aliases to Tier 1 outputs; remove the local moved file only after all workspaces have applied it.

The sample `moved.tf.example` contains 64 active `moved` blocks for two AZs and the representative `public`, `app`, `transit_gateway`, and `core_network` groups.
