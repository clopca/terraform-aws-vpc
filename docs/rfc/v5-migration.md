# terraform-aws-vpc migration guide: v4 to v5

> Status: Phase 4 implementation. Always test against a copy of production state. The v5 module does not perform state moves automatically because `moved` addresses cannot contain variables, wildcards, or generated AZ/group keys.

## Migration sequence

1. Pin the current v4 version and save `terraform state pull` outside the repository.
2. Record the exact AZs, subnet group keys/CIDRs, route destinations, NAT mode, and optional resources in state.
3. Translate inputs using the tables below. Keep all v4 group keys initially: `public`, `transit_gateway`, `core_network`, and each private group name.
4. Copy `v5/examples/migration-from-v4/moved.tf.example` into the caller root as `moved.tf`. Replace the sample AZs, private group, and destination-derived keys; remove blocks whose source is absent.
5. Upgrade the module source/version and run `terraform init -upgrade`.
6. Run `terraform plan -refresh-only`. Expect only `has moved to` records. Any create/destroy or replacement is a migration defect to resolve before apply.
7. Run the normal plan, apply, then migrate downstream references from Tier 2 aliases to Tier 1 handles.

## Variables

| v4 variable/path | v5 variable/path | Migration rule |
|---|---|---|
| `name` | `vpc.name` | Copy unchanged. |
| `create_vpc` + `vpc_id` | `vpc.id` | Create: omit/null `vpc.id`. Existing VPC: set `vpc.id`; there is no separate boolean. |
| `cidr_block` | `addressing.ipv4.cidr_block` | Primary CIDR when creating. For v4 secondary-CIDR mode, put it in `addressing.ipv4.secondary[0].cidr_block`. |
| `vpc_enable_dns_hostnames` | `vpc.dns.enable_hostnames` | Copy boolean. |
| `vpc_enable_dns_support` | `vpc.dns.enable_support` | Copy boolean. |
| `vpc_instance_tenancy` | `vpc.instance_tenancy` | Copy unchanged. |
| `vpc_ipv4_ipam_pool_id` | `addressing.ipv4.ipam_pool_id` | Copy with netmask length. |
| `vpc_ipv4_netmask_length` | `addressing.ipv4.netmask_length` | Convert the v4 string value to a number. |
| `vpc_assign_generated_ipv6_cidr_block` | `addressing.ipv6.amazon_assigned` | Copy as boolean. |
| `vpc_ipv6_cidr_block` | `addressing.ipv6.cidr_block` | Copy unchanged. |
| `vpc_ipv6_ipam_pool_id` | `addressing.ipv6.ipam_pool_id` | Copy with netmask length. |
| `vpc_ipv6_netmask_length` | `addressing.ipv6.netmask_length` | Convert the v4 string value to a number. |
| `vpc_secondary_cidr` | `addressing.ipv4.secondary` | Replace the boolean with an explicit list entry. The v4 module supported one association; v5 supports a list. |
| `vpc_secondary_cidr_natgw` | `nat_gateway.existing_ids` | Convert `{ az = { id = "nat-*" } }` to `{ az = "nat-*" }`; set the matching NAT mode/AZ. |
| `az_count` | `availability_zones.count` | Development only. Explicit names are recommended for stable state. |
| `azs` | `availability_zones.names` | Copy unchanged; this is the production migration path. |
| `subnets.<key>.netmask` | `subnets.<key>.ipv4.netmask` | Add `role`; preserve `<key>`. Pin with `cidr_index` or, preferably, migrate with explicit current CIDRs. |
| `subnets.<key>.cidrs` | `subnets.<key>.ipv4.cidrs` | Copy exact state CIDRs in AZ order. |
| `subnets.<key>.assign_ipv6_cidr` | `subnets.<key>.ipv6.cidrs` + `auto_assign` | Read the existing `/64` prefixes from state, copy them explicitly, and set `auto_assign = true`. |
| `subnets.<key>.ipv6_cidrs` | `subnets.<key>.ipv6.cidrs` | Copy exact prefixes; set `auto_assign` to preserve address assignment behavior. |
| `subnets.<key>.ipv6_native` | `subnets.<key>.ipv6.native_only` | Set true and provide the existing explicit IPv6 CIDRs. |
| `subnets.<key>.assign_ipv6_address_on_creation` | `subnets.<key>.ipv6.auto_assign` | Copy boolean; v5 uses the typed IPv6 block. |
| `subnets.<key>.enable_resource_name_dns_aaaa_record_on_launch` | no direct v5 equivalent | Remove. This undocumented v4 private-group passthrough is not part of the v5 contract. |
| `subnets.<key>.name_prefix` | `subnets.<key>.name_prefix` | Copy unchanged; never rename the map key during the first migration. |
| `subnets.<key>.tags` | `subnets.<key>.tags` | Copy unchanged. |
| implicit key class | `subnets.<key>.role` | `public` -> `public`; `transit_gateway` -> `transit_gateway`; `core_network` -> `core_network`; every other v4 key -> normally `private` (use `isolated` only after removing all routes). |
| `subnets.public.connect_to_igw` | `subnets.public.routing.internet_gateway` | Copy boolean; null still defaults true for the public role. |
| `subnets.public.map_public_ip_on_launch` | `subnets.public.public_options.map_public_ip` | Copy boolean. |
| `subnets.public.nat_gateway_configuration` | `nat_gateway.mode` | Copy `none`, `single_az`, or `all_azs`. For `single_az`, set `nat_gateway.az` to the v4 first AZ explicitly. |
| `subnets.<private>.connect_to_public_natgw` | `subnets.<private>.routing.nat_gateway` | Copy boolean. |
| `subnets.<private>.connect_to_eigw` | `subnets.<private>.routing.egress_only_igw` | Copy boolean. |
| `vpc_egress_only_internet_gateway` | derived from `subnets[*].routing.egress_only_igw` | Remove the top-level switch; v5 creates EIGW when any group requests it. |
| `subnets.transit_gateway.connect_to_public_natgw` | `subnets.transit_gateway.routing.nat_gateway` | v4 accepts a bool in implementation; copy as boolean. |
| `subnets.transit_gateway.transit_gateway_default_route_table_association` | `subnets.transit_gateway.transit_gateway_options.default_route_table_association` | Copy boolean. |
| `subnets.transit_gateway.transit_gateway_default_route_table_propagation` | `subnets.transit_gateway.transit_gateway_options.default_route_table_propagation` | Copy boolean. |
| `subnets.transit_gateway.transit_gateway_appliance_mode_support` | `subnets.transit_gateway.transit_gateway_options.appliance_mode_support` | Convert `"enable"`/`"disable"` to boolean. |
| `subnets.transit_gateway.transit_gateway_dns_support` | `subnets.transit_gateway.transit_gateway_options.dns_support` | Convert `"enable"`/`"disable"` to boolean. |
| `subnets.transit_gateway.transit_gateway_security_group_referencing_support` | `subnets.transit_gateway.transit_gateway_options.security_group_referencing` | Convert `"enable"`/`"disable"` to boolean. |
| `transit_gateway_id` | `subnets.transit_gateway.transit_gateway_options.id` | Move under the attachment subnet group. |
| `transit_gateway_routes.<group>` | `subnets.<group>.routing.transit_gateway` | Wrap the single CIDR/prefix-list ID in a list. |
| `transit_gateway_ipv6_routes.<group>` | `subnets.<group>.routing.transit_gateway_ipv6` | Wrap the single destination in a list. |
| `subnets.core_network.connect_to_public_natgw` | `subnets.core_network.routing.nat_gateway` | Copy boolean. |
| `subnets.core_network.appliance_mode_support` | `subnets.core_network.core_network_options.appliance_mode` | Copy boolean. |
| `subnets.core_network.require_acceptance` | `subnets.core_network.core_network_options.require_acceptance` | Copy boolean. |
| `subnets.core_network.accept_attachment` | `subnets.core_network.core_network_options.accept_attachment` | Copy boolean; cross-account acceptance remains external. |
| `core_network.id` / `core_network.arn` | `subnets.core_network.core_network_options.id` / `.arn` | Move under the attachment subnet group. |
| `core_network_routes.<group>` | `subnets.<group>.routing.core_network` | Wrap the single destination in a list. |
| `core_network_ipv6_routes.<group>` | `subnets.<group>.routing.core_network_ipv6` | Wrap the single destination in a list. |
| `vpc_flow_logs` | `flow_logs.default` | Use stable key `default`; the remaining rows map every field. |
| `vpc_flow_logs.name_override` | `flow_logs.default.cloudwatch_options.name` | For CloudWatch, set the exact desired log-group name. Other destination names are externally managed. |
| `vpc_flow_logs.log_destination` | `flow_logs.default.destination_arn` | Rename; required for externally managed S3/Firehose. |
| `vpc_flow_logs.iam_role_arn` | `flow_logs.default.iam_role_arn` | Copy for CloudWatch; omit to create the v5 role. |
| `vpc_flow_logs.kms_key_id` | `flow_logs.default.cloudwatch_options.kms_key_id` | Copy for CloudWatch. S3/Firehose encryption belongs to the external destination. |
| `vpc_flow_logs.log_destination_type` | `flow_logs.default.destination_type` | Map `cloud-watch-logs` -> `cloudwatch`, `s3` -> `s3`; `none` -> omit/disable the map entry. v5 additionally supports `kinesis`. |
| `vpc_flow_logs.log_format` | `flow_logs.default.log_format` | Copy unchanged. |
| `vpc_flow_logs.retention_in_days` | `flow_logs.default.cloudwatch_options.retention_in_days` | Copy for CloudWatch. |
| `vpc_flow_logs.log_bucket_lifecycle_filter_prefix` | no direct v5 equivalent | S3 lifecycle is owned by the external bucket/logging module. |
| `vpc_flow_logs.tags` | `flow_logs.default.tags` | Copy unchanged. |
| `vpc_flow_logs.traffic_type` | `flow_logs.default.traffic_type` | Copy `ALL`, `ACCEPT`, or `REJECT`. |
| `vpc_flow_logs.destination_options.file_format` | `flow_logs.default.s3_options.file_format` | Copy for S3. |
| `vpc_flow_logs.destination_options.hive_compatible_partitions` | `flow_logs.default.s3_options.hive_compatible_partitions` | Copy for S3. |
| `vpc_flow_logs.destination_options.per_hour_partition` | `flow_logs.default.s3_options.per_hour_partition` | Copy for S3. |
| `vpc_lattice.service_network_identifier` | `vpc_lattice.service_network_identifier` | Copy unchanged. |
| `vpc_lattice.security_group_ids` | `vpc_lattice.security_group_ids` | Convert list to set semantics (ordering is ignored). |
| `vpc_lattice.tags` | `vpc_lattice.tags` | Copy unchanged. |
| `optimize_subnet_cidr_ranges` | no direct equivalent | Removed. v5 uses explicit CIDRs (recommended) or deterministic netmask allocation with optional `cidr_index`. |
| `tags` | `tags` | Copy unchanged. |

## Outputs

| v4 output | v5 migration target | Shape/notes |
|---|---|---|
| `vpc_attributes` | Tier 2 `vpc_attributes`; then Tier 1 `vpc_id`, `vpc_arn`, `vpc_cidr_block` | Tier 2 remains a full provider object. |
| `azs` | Tier 1 `azs` | Exact `list(string)`. |
| `transit_gateway_attachment_id` | Tier 1 `transit_gateway_attachment_id` | Exact scalar/null shape. |
| `core_network_attachment` | Tier 2 `core_network_attachment`; then Tier 1 `core_network_attachment_id` | Tier 2 remains the full object. |
| `private_subnet_attributes_by_az` | Tier 2 same name; then `subnet_ids_by_group_by_az` / `subnet_cidrs_by_group_by_az` | Exact composite keys `<group>/<az>` in Tier 2. |
| `public_subnet_attributes_by_az` | Tier 2 same name; then group/semantic Tier 1 subnet outputs | Exact AZ keys when the group remains named `public`. |
| `tgw_subnet_attributes_by_az` | Tier 2 same name; then group/semantic Tier 1 subnet outputs | Exact AZ keys when the group remains named `transit_gateway`. |
| `core_network_subnet_attributes_by_az` | Tier 2 same name; then group/semantic Tier 1 subnet outputs | Exact AZ keys when the group remains named `core_network`. |
| `rt_attributes_by_type_by_az` | Tier 2 same name; then Tier 1 route-table ID outputs | Exact outer keys; `private` retains `<group>/<az>`, reserved groups retain AZ keys. |
| `nat_gateway_attributes_by_az` | Tier 2 same name; then `nat_gateway_ids`, `nat_public_ips`, `nat_private_ips`, `nat_eip_allocation_ids` | Tier 2 rekeys v5 `nat/<az>` objects back to AZ. |
| `natgw_id_per_az` | Tier 2 same name; then `nat_gateway_ids` | Exact `{ az = { id = string } }`; single-AZ IDs are duplicated across AZs. |
| `internet_gateway` | Tier 2 same name; then `internet_gateway_id` | Tier 2 full object for module-created IGW. |
| `egress_only_internet_gateway` | Tier 2 same name; then `egress_only_igw_id` | Tier 2 full object. |
| `vpc_lattice_service_network_association` | Tier 2 same name; then Tier 1 association ID | Tier 2 full object. |
| `flow_log_attributes` | Tier 2 same name; then `flow_log_ids["default"]` | Tier 2 selects key `default` or the only configured Flow Log. |

## State address rules

`moved` blocks are exact and static. v4 used AZ-only keys for reserved subnet types and NAT, composite `<private-group>/<az>` keys for private subnets, and `count` index `[0]` for attachments. v5 uses:

- subnets, route tables, associations: `<group>/<az>`;
- EIPs/NAT: `nat/<az>`;
- TGW/CWAN attachments and Lattice: `"vpc"`;
- Flow Logs: caller key, conventionally `"default"`;
- routes: `<group>/<az>/<target>` plus a destination suffix for TGW/CWAN.

The example contains all exact mappings for a two-AZ representative state. Repeat each per-AZ block for the real AZ set and each private group. Destination key suffixes use `replace(destination, "/", "-")` (for example `10.0.0.0/8` -> `10.0.0.0-8`). `aws_vpc.main[0]` and `aws_internet_gateway.main[0]` keep their address and need no block.

A v4 secondary association moves as follows when that mode is used:

```hcl
moved {
  from = module.vpc.aws_vpc_ipv4_cidr_block_association.secondary[0]
  to   = module.vpc.aws_vpc_ipv4_cidr_block_association.secondary["0"]
}
```

## Cases that cannot use `moved`

| v4 state | v5 disposition | Why / workaround |
|---|---|---|
| `module.vpc.module.flow_logs[0].module.cloudwatch_log_group[0].aws_iam_policy.main` | `module.vpc.aws_iam_role_policy.flow_logs["default"]` | Resource type changes from managed `aws_iam_policy` to inline `aws_iam_role_policy`; neither `moved` nor `terraform state mv` can change type. Let v5 create the inline policy, then detach/destroy the old managed policy. If an equivalent inline policy already exists, import it as `ROLE_NAME:POLICY_NAME` before plan. |
| `...aws_iam_role_policy_attachment.main` | no v5 resource | v5 attaches no managed policy. Let Terraform remove the attachment after the inline policy exists; remove the orphaned policy explicitly if lifecycle ownership was transferred. |
| v4-created S3 Flow Log bucket and its public-access, encryption, and lifecycle resources | caller-owned logging module/resource | v5 intentionally does not own durable S3/Firehose destinations. Move same-type resources with `terraform state mv` into a new caller-owned logging resource/module address, or import them there, then pass the bucket ARN as `flow_logs.default.destination_arn`. Do not allow Terraform to destroy a log archive. |
| Any address whose destination is an injected ID (`vpc.id`, `vpc.igw_id`, `nat_gateway.existing_ids`, `subnets[*].route_table_id`) | no managed destination resource | Injection removes lifecycle ownership. Use `terraform state rm` only after the target is represented in another state, or first `terraform state mv`/import it into its new owning configuration. |
| Route whose v4 destination or v5 route list changed during migration | no safe one-to-one block | Freeze destinations for the migration. If already changed, import the AWS route into the final v5 address where supported, or allow a reviewed delete/create during a maintenance window. |

`terraform state mv` is appropriate only when source and destination have the same resource type. Prefer declarative `moved` blocks for repeatability and retain them until every workspace has applied the upgrade.
