# terraform-aws-vpc migration guide: v4 to v5

> Status: Phase 5 implementation. Always test against a copy of production state. The v5 module does not perform state moves automatically because `moved` addresses cannot contain variables, wildcards, or generated AZ/group keys. `v5/tests/migration.tftest.hcl` verifies representative moves against shared ephemeral state and plans the complete 63-block example with a mock provider; the CloudWatch remove/import cutover remains an explicit operator procedure because import blocks are root-module-only.

## Migration safety contract

- Work against a copy of production state first; never combine an unreviewed provider upgrade with the v4 -> v5 module cutover.
- The migration gate is a complete normal `terraform plan`, not `-refresh-only`. Refresh-only cannot prove convergence to the v5 configuration.
- Preserve every durable physical ID. The default gate permits zero replacements. The only expected creates/deletes are the staged Flow Logs IAM policy conversion described below.
- Do not run `apply` between removing the old CloudWatch log-group state address and importing the same physical group at its v5 address.

## Migration sequence

### A. Baseline Terraform and the AWS provider while still on v4

1. Pin the current v4 module version and back up state outside the repository:

   ```shell
   terraform state pull > /secure/backup/vpc-v4-before-provider-upgrade.tfstate
   terraform state list > /secure/backup/vpc-v4-addresses.txt
   ```

2. Still using v4 configuration, upgrade only the intended Terraform/AWS provider versions. Run a **normal** plan, review/apply provider-only changes, and repeat until clean:

   ```shell
   terraform init -upgrade
   terraform plan -out=v4-provider-upgrade.tfplan
   terraform apply v4-provider-upgrade.tfplan
   terraform plan -detailed-exitcode
   # Required result: exit code 0.
   ```

   Commit the provider lock change separately. Do not change the module source/version in this step.

### B. Capture v4 identity and ordering

3. Record physical IDs, route destinations, optional resources, subnet keys/CIDRs, and the exact observable AZ order. `availability_zones.names` and every explicit CIDR list in v5 must use this order; do not reconstruct it from the textual v4 input:

   ```shell
   terraform console <<<'module.vpc.azs'
   terraform state list
   ```

4. For a v4-created CloudWatch Flow Logs destination, capture the generated physical log-group name and the IAM role's configured `name_prefix` **before** changing module versions:

   ```shell
   terraform state show \
     'module.vpc.module.flow_logs[0].module.cloudwatch_log_group[0].aws_cloudwatch_log_group.main'
   terraform state show \
     'module.vpc.module.flow_logs[0].module.cloudwatch_log_group[0].aws_iam_role.main'
   ```

   Copy the log group's `name` value to `flow_logs.default.cloudwatch_options.name`. Copy the role's `name_prefix` value (not its generated `name`) to `flow_logs.default.role_name_prefix`. Both are ForceNew naming inputs; exact preservation is required for a zero-replacement cutover.

### C. Translate configuration and state

5. Translate inputs using the tables below. Keep the v4 group keys initially: `public`, `transit_gateway`, `core_network`, and each private group name. Use explicit current subnet CIDRs and the observed AZ order.
6. Copy the active `v5/examples/migration-from-v4/moved.tf` into the caller root. Replace sample AZs, private groups, and destination-derived keys; remove every block whose source is absent. The example has 63 moves and intentionally excludes the v4 CloudWatch log group.
7. Change the module source/version and initialize v5 without changing the already-baselined provider selection:

   ```shell
   terraform init
   ```

8. Preserve the v4-generated CloudWatch log group by re-addressing it through remove/import. This changes state only; it does not delete the AWS log group. Take a fresh backup, perform both commands consecutively, and do not plan/apply between them:

   ```shell
   terraform state pull > /secure/backup/vpc-v4-before-flow-log-import.tfstate
   terraform state rm \
     'module.vpc.module.flow_logs[0].module.cloudwatch_log_group[0].aws_cloudwatch_log_group.main'
   terraform import \
     'module.vpc.aws_cloudwatch_log_group.flow_logs["default"]' \
     "$V4_FLOW_LOG_GROUP_NAME"
   ```

   Keep the IAM role moved block active and the exact `role_name_prefix` configured. The role's generated physical `name` and ID must remain unchanged.

### D. Complete-plan gate

9. Run and save a **complete normal plan**:

   ```shell
   terraform plan -out=v5-migration.tfplan
   terraform show -no-color v5-migration.tfplan > v5-migration.txt
   ```

   The gate criteria are:

   - **Required:** zero `replace` actions; no create/delete for VPC, subnets, route tables, NAT gateways/EIPs, gateways, attachments, CloudWatch log group, or IAM role; no destruction of S3 buckets or any log archive.
   - **Expected state-only records:** the selected `moved` pairs. Re-keyed routes whose destination is unchanged have no residual create/delete.
   - **Allowed create:** `module.vpc.aws_iam_role_policy.flow_logs["default"]` for a module-created CloudWatch role.
   - **Allowed later deletes:** the old managed-policy attachment and managed policy, but only after the inline policy exists and delivery is verified.
   - **Allowed in-place updates, when explicitly reviewed:** IAM role trust policy, description, and tags; Flow Log tags/traffic type/log format/aggregation interval; CloudWatch retention, KMS key, and tags. Keep values identical if these changes are not intended.
   - **Exceptional route residual:** delete/create is allowed only for a route destination deliberately changed during migration, enumerated by address and approved for a maintenance window. With frozen destinations the expected residual is zero.

   Any other create/delete, and every replacement, fails the gate.

### E. Ordered IAM permissions cutover

10. A single graph does not order deletion of the old managed-policy attachment after creation of the new inline policy. Guarantee the order with a first targeted apply that creates only the v5 inline policy and its dependencies; the old attachment remains in state:

    ```shell
    terraform apply \
      -target='module.vpc.aws_iam_role_policy.flow_logs["default"]'
    ```

11. Verify that `publish-vpc-flow-logs` is attached inline to the preserved role and that the existing Flow Log continues delivering new events to the preserved group. Then run a new complete plan. Only now may it retire the old attachment/managed policy plus apply the previously approved in-place updates:

    ```shell
    terraform plan -out=v5-migration-final.tfplan
    terraform apply v5-migration-final.tfplan
    ```

    The targeted apply is a migration-only ordering barrier, not a normal operating practice.

### F. Post-apply verification

12. Compare the saved v4 inventory with v5 state: VPC, subnet, route-table, NAT/EIP, gateway, attachment, Flow Log, log-group, and IAM-role physical IDs must be preserved. Confirm no v4 module addresses remain:

    ```shell
    terraform state list | grep 'module.vpc.module.flow_logs' && exit 1 || true
    terraform state show 'module.vpc.aws_flow_log.this["default"]'
    terraform state show 'module.vpc.aws_cloudwatch_log_group.flow_logs["default"]'
    terraform state show 'module.vpc.aws_iam_role.flow_logs["default"]'
    ```

13. Verify the Flow Log reports `ACTIVE` and that the preserved CloudWatch group receives events newer than the cutover. Finally require a clean complete plan:

    ```shell
    terraform plan -detailed-exitcode
    # Required result: exit code 0.
    ```

14. Migrate downstream references from Tier 2 aliases to Tier 1 handles. Retain the caller's moved file until every workspace has applied the upgrade.

## ADR-F4-1: preserve the v4 Flow Logs destination and role

**Status:** accepted for the v4 -> v5 migration gate.

**Decision:** preserve the existing CloudWatch log group by configuring its exact generated physical `name`, removing only its old state address, and importing it at the v5 fixed-name address. Preserve the IAM role with a moved block plus the exact v4 `name_prefix`. Convert the managed policy to the v5 inline policy in two applies: create and verify inline permissions first, then retire the old attachment/policy in the complete apply.

**Rationale:** v4 configures the log group with `name_prefix`; v5 configures it with `name`. Both provider attributes are ForceNew, so a moved block alone still proposes replacement even when the resulting physical name is known. Remove/import normalizes state to the v5 naming argument while retaining the same group, history, ARN, and Flow Log destination. The IAM role uses `name_prefix` on both versions and can be moved without replacement when its exact prefix is preserved. The two-stage policy cutover is the only deterministic way to avoid a permissions gap because Terraform has no dependency edge from deletion of the old attachment to creation of the new inline policy.

**Rejected default:** creating a new group (with create-before-destroy behavior or an accepted replacement) splits continuity at cutover. Historical logs remain in the old group only if that group is deliberately removed from Terraform ownership rather than destroyed; callers must then retain and eventually clean it up. This remains an opt-in maintenance-window fallback, not the migration default.

**Consequences:** the runbook has two explicit state commands and one targeted migration apply, all protected by state backups and complete plans. The default path has zero replacement of the log group or IAM role and no delivery-permission window.

## Variables

| v4 variable/path | v5 variable/path | Migration rule |
|---|---|---|
| `name` | `vpc.name` | Copy unchanged. |
| `create_vpc` + `vpc_id` | `vpc.create` + `vpc.id` | Create: keep `create=true` and `id=null`. Existing VPC: set `create=false` and `id`; the ID may be computed upstream. |
| `cidr_block` | `addressing.ipv4.cidr_block` | Primary CIDR when creating. For v4 secondary-CIDR mode, put it in a stable caller-owned entry such as `addressing.ipv4.secondary.legacy.cidr_block`. |
| `vpc_enable_dns_hostnames` | `vpc.dns.enable_hostnames` | Copy boolean. |
| `vpc_enable_dns_support` | `vpc.dns.enable_support` | Copy boolean. |
| `vpc_instance_tenancy` | `vpc.instance_tenancy` | Copy unchanged. |
| `vpc_ipv4_ipam_pool_id` | `addressing.ipv4.ipam_pool_id` | Copy with netmask length. |
| `vpc_ipv4_netmask_length` | `addressing.ipv4.netmask_length` | Convert the v4 string value to a number. |
| `vpc_assign_generated_ipv6_cidr_block` | `addressing.ipv6.amazon_assigned` | Copy as boolean. |
| `vpc_ipv6_cidr_block` | `addressing.ipv6.cidr_block` | Copy unchanged. |
| `vpc_ipv6_ipam_pool_id` | `addressing.ipv6.ipam_pool_id` | Copy with netmask length. |
| `vpc_ipv6_netmask_length` | `addressing.ipv6.netmask_length` | Convert the v4 string value to a number. |
| `vpc_secondary_cidr` | `addressing.ipv4.secondary` | Replace the boolean with a stable-keyed map entry such as `legacy = { cidr_block = ... }`. v5 supports multiple named associations without positional state churn. |
| `vpc_secondary_cidr_natgw` | `nat_gateway.create=false` + `existing_ids` | Convert `{ az = { id = "nat-*" } }` to `{ az = "nat-*" }`; set inject mode plus matching NAT mode/AZ. |
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
| `vpc_egress_only_internet_gateway` | `subnets[*].routing.egress_only_igw` + `vpc.eigw_create`/`eigw_id` | Copy routing intent. Keep create mode for a moved v4 EIGW; use `eigw_create=false` plus ID only when ownership moves outside this module. |
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
| `vpc_flow_logs.name_override` or v4 generated log-group name | `flow_logs.default.cloudwatch_options.name` | Set the exact physical `name` reported by `terraform state show`, not merely the old prefix. Preserve the group with remove/import; do not use a moved block from `name_prefix` to `name`. |
| v4 generated CloudWatch IAM role `name_prefix` | `flow_logs.default.role_name_prefix` | Copy the exact `name_prefix` reported by state (not the generated role `name`) before applying the IAM role moved block. |
| `vpc_flow_logs.log_destination` | `flow_logs.default.create_destination=false` + `destination_arn` | CloudWatch injection sets the explicit flag; S3/Firehose remain externally managed and always require the ARN. |
| `vpc_flow_logs.iam_role_arn` | `flow_logs.default.create_iam_role=false` + `iam_role_arn` | Set both for CloudWatch role injection; keep `create_iam_role=true` to create the v5 role. |
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
| `vpc_lattice.service_network_identifier` | `vpc_lattice.enabled=true` + `service_network_identifier` | Enable explicitly, then copy the identifier; it may be computed upstream. |
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

The active example contains 63 exact mappings for a two-AZ representative state. Repeat each per-AZ block for the real AZ set and each private group. Destination key suffixes use `replace(destination, "/", "-")` (for example `10.0.0.0/8` -> `10.0.0.0-8`). `aws_vpc.main[0]` and `aws_internet_gateway.main[0]` keep their address and need no block. The CloudWatch log group uses the ADR-F4-1 remove/import procedure instead of a moved block.

A v4 secondary association moves as follows when that mode is used:

```hcl
moved {
  from = module.vpc.aws_vpc_ipv4_cidr_block_association.secondary[0]
  to   = module.vpc.aws_vpc_ipv4_cidr_block_association.secondary["legacy"]
}
```

Configure the matching contract key before the move:

```hcl
addressing = {
  ipv4 = {
    secondary = {
      legacy = { cidr_block = "100.64.0.0/16" }
    }
  }
}
```

A subnet that consumes this range sets `ipv4.secondary_cidr_key = "legacy"`;
that selector establishes the association dependency for a normal apply.

## Cases that cannot use `moved`

| v4 state | v5 disposition | Why / workaround |
|---|---|---|
| `module.vpc.module.flow_logs[0].module.cloudwatch_log_group[0].aws_cloudwatch_log_group.main` | `module.vpc.aws_cloudwatch_log_group.flow_logs["default"]` | Both resources have the same type, but v4 `name_prefix` -> v5 `name` is ForceNew and therefore unsafe with `moved`. Capture the generated `name`, configure it as `cloudwatch_options.name`, remove only the old state address, and import the same group at the v5 address as specified by ADR-F4-1. |
| `...aws_iam_role.main` | `module.vpc.aws_iam_role.flow_logs["default"]` | Keep the moved block, but first configure `role_name_prefix` with the exact v4 state `name_prefix`. Trust policy, description, and tags may update in place; the role ID and generated name must not change. |
| `module.vpc.module.flow_logs[0].module.cloudwatch_log_group[0].aws_iam_policy.main` | `module.vpc.aws_iam_role_policy.flow_logs["default"]` | Resource type changes from managed `aws_iam_policy` to inline `aws_iam_role_policy`; neither `moved` nor `terraform state mv` can change type. After the complete-plan gate, target-create the inline policy first and verify delivery. Only a later complete apply may destroy the old managed policy. If an equivalent inline policy already exists, import it as `ROLE_NAME:POLICY_NAME` before plan. |
| `...aws_iam_role_policy_attachment.main` | no v5 resource | v5 attaches no managed policy. Keep the attachment through the targeted inline-policy apply; remove it only in the subsequent reviewed complete apply after delivery verification. |
| v4-created S3 Flow Log bucket and its public-access, encryption, and lifecycle resources | caller-owned logging module/resource | v5 intentionally does not own durable S3/Firehose destinations. Move same-type resources with `terraform state mv` into a new caller-owned logging resource/module address, or import them there, then pass the bucket ARN as `flow_logs.default.destination_arn`. Do not allow Terraform to destroy a log archive. |
| Any address whose destination is an injected ID (`vpc.create=false`, `vpc.igw_create=false`, `nat_gateway.create=false`, `subnets[*].manage_route_table=false`) | no managed destination resource | Injection removes lifecycle ownership; the paired ID fields may be computed. Use `terraform state rm` only after the target is represented in another state, or first `terraform state mv`/import it into its new owning configuration. |
| Route whose v4 destination or v5 route list changed during migration | no safe one-to-one block | Freeze destinations for the migration. If already changed, import the AWS route into the final v5 address where supported, or allow a reviewed delete/create during a maintenance window. |

`terraform state mv` is appropriate only when source and destination have the same resource type. Prefer declarative `moved` blocks for repeatability and retain them until every workspace has applied the upgrade.
