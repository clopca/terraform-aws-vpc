# VPC v5 contract

## Late-bound top-level routes

The top-level `routes` map adds routes after subnet and route-table identity has
been established. It is separate from `subnets[*].routes` so a target can be
produced by a module or resource that consumes this VPC's subnet outputs in the
same Terraform plan.

```hcl
routes = {
  inspected-default = {
    from_group = "application"
    destination = {
      type  = "ipv4_cidr"
      value = "0.0.0.0/0"
    }
    target = {
      type      = "vpc_endpoint"
      ids_by_az = module.network_firewall.endpoint_ids_by_az
    }
  }
}
```

Each route map key is caller-owned state identity and must not contain `/`.
For module-managed route tables, expansion produces one `aws_route.top_level`
instance per configured Availability Zone with the address key
`<route-key>/<az>`. An injected route table is one shared physical table across
all subnets and AZs, so a static `target.id` produces exactly one instance keyed
`<route-key>/shared`. `target.ids_by_az` is rejected for injected tables because
one physical table cannot select a different target by AZ. Resource keys are
derived only from caller-owned route, AZ, and shared-table identities;
route-table and target IDs remain values and may be unknown during planning.

### Changing `manage_route_table` after deployment

Changing `subnets.<group>.manage_route_table` is an ownership handoff, not an
in-place toggle. A direct change from `true` to `false` removes the managed
`aws_route_table.main["<group>/<az>"]` instances from configuration. Without an
explicit handoff, Terraform plans to destroy those route tables. Preserve each
physical table that must survive by adding a root-module `removed` block in
the same configuration that performs the transition:

```hcl
removed {
  from = module.vpc.aws_route_table.main["application/us-east-1a"]

  lifecycle {
    destroy = false
  }
}
```

Repeat the block for every managed AZ, choose the one physical table that will
become the shared injected table, and pass its stable identity through
`route_table_key` and `route_table_id`. Rehearse against copied state and verify
that every subnet association moves to the intended shared table; any preserved
non-selected tables remain caller-owned and require deliberate later cleanup.

The same change re-keys every top-level route for that group from
`<route-key>/<az>` to `<route-key>/shared`. In the normal direct plan, Terraform
destroys the old zonal route instances and creates the shared instance. Use that
plan only in a maintenance window where a temporary route interruption is
acceptable. If continuity is required, stage the handoff: move the selected
table's existing route state to the `/shared` address with a caller-owned
`moved` block, apply and verify the association/ownership change, then remove
obsolete routes and tables in a separate reviewed change. Never apply the
boolean change as an assumed zero-destroy migration.

`from_group` must name an entry in `subnets`. Its effective route tables receive
the route. The destination union is identical to `subnets[*].routes`:
`ipv4_cidr`, `ipv6_cidr`, or `prefix_list`. The target union is also identical:
`vpc_peering`, `vpc_endpoint`, `network_interface`,
`virtual_private_gateway`, `local_gateway`, or `carrier_gateway`.

Exactly one target ID form is required:

- `id` applies one target ID to every module-managed AZ, or once to an injected
  shared table.
- `ids_by_az` selects the target ID matching each AZ and requires module-managed
  per-AZ tables. Every configured AZ must be present; a plan failure lists all
  missing AZs.

A physical route table may have only one generic route declaration for a given
destination. Collision checks cover `subnets[*].routes` against top-level
`routes`, as well as pairs of top-level entries, and diagnostics name both caller
keys. Top-level routes are rejected for `isolated` groups and for injected
physical route tables shared with an isolated group.

Gateway endpoints add service-managed prefix-list routes as a side effect of the
route-table association. Their prefix-list IDs are not available to this module
as plan-known values, so it cannot prove that a top-level `prefix_list`
destination differs from S3 or DynamoDB. A top-level prefix-list route is
therefore rejected on any table with a gateway endpoint association unless that
route sets `acknowledge_gateway_endpoint_coexistence = true`. The acknowledgement
means the caller has independently verified that the explicit prefix list is
distinct and accepts responsibility for future service or configuration changes.

The AWS provider also constrains destination/target pairs. Within this contract,
`prefix_list` cannot target `vpc_endpoint`, and `ipv6_cidr` cannot target
`carrier_gateway`; both combinations fail variable validation before provider
planning.

### Choosing the route surface

If the target is produced by a module or resource that consumes subnet outputs
from this VPC, declare it in top-level `routes`. Otherwise, keep routing intent
co-located in `subnets.<group>.routes`.

### Dependency direction

Top-level `routes` may feed only their dedicated `aws_route` resources and
validation-only `terraform_data` resources. They never feed subnet resources,
route-table resources, or module outputs. This one-way dependency boundary allows
a firewall to consume VPC subnet outputs and return computed zonal endpoint IDs
without creating a Terraform dependency cycle. Before any top-level route is
written, Terraform completes injected physical-identity validation and every
applicable isolation and route-compatibility guard. This explicit ordering keeps
computed aliases fail-closed at apply time rather than allowing a partial route
write before identity comparison finishes.
