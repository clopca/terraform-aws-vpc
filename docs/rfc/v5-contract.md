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
