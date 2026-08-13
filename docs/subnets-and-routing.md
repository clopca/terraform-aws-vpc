# Subnets and routing

Subnet groups combine address allocation, semantic role, route-table ownership, and routing intent under one stable caller key. The role controls allowed behavior; the key controls Terraform state identity.

## Subnet group identity

A subnet key such as `application` produces addresses shaped as `<group>/<az>` for subnets, managed route tables, and associations. Renaming the key is a state migration, even when `name_prefix` or tags preserve the same display name.

```hcl
subnets = {
  application = {
    role        = "private"
    name_prefix = "app"
    ipv4        = { netmask = 24 }
  }
}
```

Use `name_prefix` and `name_format` for display changes. Use caller-root `moved` blocks before changing a deployed map key.

Subnet resources also support create or inject ownership. `create = false` requires existing subnet IDs keyed by every selected AZ; the module can then manage the selected route-table associations and routes without owning the subnets.

## Semantic roles

| Role | Intended behavior |
| --- | --- |
| `public` | Internet Gateway routing and optional public NAT hosting. `map_public_ip` remains opt-in. |
| `private` | Optional NAT, egress-only gateway, TGW, Cloud WAN, and service routing. |
| `isolated` | No Internet, NAT, egress-only gateway, TGW, Cloud WAN, or generic routes. S3 and DynamoDB gateway endpoints are allowed. |
| `transit_gateway` | Dedicated attachment subnets selected by one or more TGW attachments. |
| `core_network` | Dedicated subnets for the single Cloud WAN VPC attachment. |

Multiple groups may share a role. At most one group may use `core_network` because the Cloud WAN attachment boundary is singular.

## Managed and injected route tables

Managed mode is the default and creates one route table per subnet and AZ. Injected mode uses all three fields:

```hcl
subnets = {
  public = {
    role               = "public"
    ipv4               = { netmask = 24 }
    manage_route_table = false
    route_table_key    = "shared-public"
    route_table_id     = module.network_foundation.public_route_table_id
    routing = {
      internet_gateway = true
    }
  }
}
```

`route_table_key` is caller-owned state identity for routes and gateway-endpoint associations on the physical table. Groups sharing one physical table must use the same key and ID; the module creates each selected route or endpoint association once.

An injected route table may be a computed upstream value because `manage_route_table` fixes ownership and cardinality before the ID is known.

## Fail-closed isolated tables

The module always rejects an injected route table for an `isolated` group unless `isolated_accepts_uninspected_route_table = true`. The AWS provider's route-table data source does not expose every propagated or service-managed route class, so plan-time inspection cannot prove that an unmanaged table is isolated.

The opt-in is intentionally dangerous: it transfers responsibility for every existing and future route on that table to the caller. Use it only after external controls continuously enforce the isolation policy. A successful Terraform plan is not evidence that the injected table has no transit or internet route.

## Routing declarations

Routing is co-located with each subnet group:

| Field | Effect |
| --- | --- |
| `internet_gateway` | IPv4 and public IPv6 default routes through the IGW. Defaults true only for `public`. |
| `nat_gateway` | IPv4 default route to the selected NAT topology. |
| `egress_only_igw` | IPv6 default route through an egress-only Internet Gateway. |
| `dns64` | Enables DNS64 and creates `64:ff9b::/96` routing through NAT; requires a compatible NAT path. |
| `transit_gateway_attachments` | Map of TGW attachment key to IPv4 CIDR or prefix-list destinations. |
| `transit_gateway_attachments_ipv6` | Map of TGW attachment key to IPv6 CIDR or prefix-list destinations. |
| `core_network` / `core_network_ipv6` | Destination lists routed to the Cloud WAN attachment. |
| `s3_gateway_endpoint` / `dynamodb_gateway_endpoint` | Associates the effective route table with the selected gateway endpoint. |

Destination lists must be unique within the group. `isolated` groups reject all general egress and transit fields, even when a list is supplied through a plural attachment key.

## Generic typed routes

`subnets.<group>.routes` covers targets outside the dedicated NAT, gateway, TGW, and Cloud WAN fields. The route map key is state identity; destination and target IDs remain values and may be computed:

```hcl
routes = {
  security-services = {
    destination = {
      type  = "ipv4_cidr"
      value = "198.18.0.0/15"
    }
    target = {
      type = "vpc_peering"
      id   = aws_vpc_peering_connection.security.id
    }
  }
}
```

Destination types are `ipv4_cidr`, `ipv6_cidr`, and `prefix_list`. Target types are `vpc_peering`, `vpc_endpoint`, `network_interface`, `virtual_private_gateway`, `local_gateway`, and `carrier_gateway`. Generic routes are not permitted on isolated groups.

## Gateway endpoints

`gateway_endpoints` is keyed by stable caller identity, while `service` selects the AWS service:

```hcl
gateway_endpoints = {
  object-storage = {
    service = "s3"
  }
  database = {
    service = "dynamodb"
    policy  = data.aws_iam_policy_document.dynamodb.json
  }
}
```

Only `s3` and `dynamodb` are supported, and only one endpoint per service is permitted. Conventional key names are optional; changing a key after deployment still changes state identity.

Create mode owns the endpoint and accepts an optional JSON policy. Inject mode uses `create = false` plus `endpoint_id`; the endpoint policy remains caller-owned and therefore must be omitted.

Route-table associations are selected under each subnet group's `routing` block. Gateway endpoints are allowed on isolated groups because they add service-specific private routes rather than general internet or transit reachability. S3 and DynamoDB gateway endpoints have no hourly endpoint charge, but service, transfer, and cross-AZ charges can still apply.

## Route-table constraints

- A shared injected table cannot support per-AZ NAT targets; `all_azs` NAT is rejected when a referencing group requests NAT or NAT64.
- `map_public_ip` affects ENI address assignment, not route-table classification.
- Injecting a subnet, route table, endpoint, or attachment does not transfer lifecycle ownership to this module.
- Prefix-list destinations are accepted where the typed route field documents them; validate the referenced list's contents separately.
- Keep route keys, injected table keys, endpoint keys, attachment keys, and subnet keys stable after apply.
