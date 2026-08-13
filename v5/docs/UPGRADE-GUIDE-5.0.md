# Upgrade guide: terraform-aws-vpc v4 to v5

> **Production migration runbook.** Rehearse every step against a copy of production state and keep a recoverable state backup before each address transition. The v5 module cannot generate caller-specific `moved` blocks because Terraform addresses cannot contain variables or wildcards.
>
> The implementation rationale, test-fixture evidence, and accepted design decisions remain in the internal [migration RFC](../../docs/rfc/v5-migration.md). The executable catalog is [`examples/migration-from-v4/moved.tf`](../examples/migration-from-v4/moved.tf).

## Migration safety contract

- Work against a copy of production state first; never combine an unreviewed provider upgrade with the v4 -> v5 module cutover.
- The migration gate is one saved, complete normal `terraform plan`; no partial or state-only plan is an acceptance substitute.
- Preserve every durable physical ID. The default gate permits zero replacements and zero destroys. Expected creates are internal `terraform_data` precondition records plus the Flow Logs inline policy described below; `terraform_data` has no AWS API side effects. The legacy managed policy and attachment are forgotten without destroy and cleaned explicitly only after delivery verification.
- Preserve v4 Name tags with the format mapping below. Besides eliminating the remediation-3 fixture's 14 subnet/route-table/EIP/NAT updates, set the Flow Log format to `{vpc}` and the log-group format to empty so neither logging resource changes `Name`.
- Keep provider `default_tags` unchanged through the cutover. Duplicate keys resolve provider defaults < module globals < resource/group tags < generated Name.
- Express the CloudWatch log-group ownership handoff declaratively so the old-address forget and the v5-address import are visible in the same normal plan.

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

   Commit the provider lock change separately. Do not change the module source/version in this step. Configure and converge any AWS provider `default_tags` change here, while still on v4. The provider merges defaults below explicit resource tags and exposes the union as `tags_all`; changing defaults after the module switch would mix provider tag drift with migration actions.

### B. Capture v4 identity and ordering

3. Record physical IDs, route destinations, optional resources, subnet keys/CIDRs, Name tags, tag maps, and the exact observable AZ order. `availability_zones.names` and every explicit CIDR list in v5 must use this order; do not reconstruct it from the textual v4 input:

   ```shell
   terraform console <<<'module.vpc.azs'
   terraform state list
   ```

4. For a v4-created CloudWatch Flow Logs destination, capture the generated log-group name, IAM role name/prefix, managed-policy ARN/name prefix, and attachment **before** changing module versions:

   ```shell
   terraform state show \
     'module.vpc.module.flow_logs[0].module.cloudwatch_log_group[0].aws_cloudwatch_log_group.main'
   terraform state show \
     'module.vpc.module.flow_logs[0].module.cloudwatch_log_group[0].aws_iam_role.main'
   terraform state show \
     'module.vpc.module.flow_logs[0].module.cloudwatch_log_group[0].aws_iam_policy.main'
   terraform state show \
     'module.vpc.module.flow_logs[0].module.cloudwatch_log_group[0].aws_iam_role_policy_attachment.main'
   ```

   Copy the log group's `name` to `flow_logs.default.cloudwatch_options.name` and to the declarative import ID. Copy the role's `name_prefix` (not its generated `name`) to `flow_logs.default.role_name_prefix`. Also retain the generated role `name` and managed-policy `arn` for the post-verification cleanup. The v4 defaults use `${var.name}-cw-access-role-` and `${var.name}-cw-access-policy-` prefixes; cleanup requires the complete generated values captured from state. Both log-group and role naming attributes are ForceNew when configured, so exact identity is required for a zero-replacement cutover.

   If v4 assigned IPv6, also capture `ipv6_association_id` from `module.vpc.aws_vpc.main[0]`. v4 stores this association inside the VPC resource state, while v5 owns it as a standalone keyed resource; Terraform cannot express that ownership transfer with a `moved` block.

   ```shell
   terraform state show 'module.vpc.aws_vpc.main[0]'
   # Record ipv6_association_id, for example vpc-cidr-assoc-0123456789abcdef0.
   ```

### C. Translate configuration and state

5. Translate inputs using the tables below. Keep the v4 group keys initially: `public`, `transit_gateway`, `core_network`, and each private group name. Use explicit current subnet CIDRs and the observed AZ order. Configure the exact v4 Name formats before planning: subnet groups use `"{group}-{az}"`, NAT/EIP use `"nat-{group}-{az}"`, IGW uses `"{vpc}-igw"`, EIGW uses `"{vpc}"`, the Flow Log uses `flow_logs.default.name_format = "{vpc}"`, and its generated log group uses `cloudwatch_options.name_format = ""`.
6. Copy the active `v5/examples/migration-from-v4/moved.tf` into the caller root. Replace sample AZs, private groups, and destination-derived keys. Treat 63 as the union of demonstrated features, not a required count: compare against `terraform state list`, remove every block whose source is absent, and repeat the private six-block pattern for each actual private group. The remediation-3 fixture retained 26 and omitted 37. The example intentionally excludes the v4 CloudWatch log group.
7. Change the module source/version and initialize v5 without changing the already-baselined provider selection:

   ```shell
   terraform init
   ```

8. Add three non-destructive `removed` blocks for the old log group, managed policy, and attachment, plus one declarative `import` block for the v5 log-group address alongside the caller's module block. If v4 assigned IPv6, add the second declarative import shown below for the standalone v5 association. These are root-module blocks; do not place them inside the VPC module. Replace both variable values with the physical identities captured in step 4:

   ```hcl
   variable "v4_flow_log_group_name" {
     type    = string
     default = "replace-with-the-generated-v4-log-group-name"
   }

   variable "v4_ipv6_association_id" {
     type    = string
     default = "vpc-cidr-assoc-replace-with-v4-association-id"
   }

   removed {
     from = module.vpc.module.flow_logs.module.cloudwatch_log_group.aws_cloudwatch_log_group.main

     lifecycle {
       destroy = false
     }
   }

   removed {
     from = module.vpc.module.flow_logs.module.cloudwatch_log_group.aws_iam_policy.main

     lifecycle {
       destroy = false
     }
   }

   removed {
     from = module.vpc.module.flow_logs.module.cloudwatch_log_group.aws_iam_role_policy_attachment.main

     lifecycle {
       destroy = false
     }
   }

   import {
     to = module.vpc.aws_cloudwatch_log_group.flow_logs["default"]
     id = var.v4_flow_log_group_name
   }

   # Include only when the v4 VPC has IPv6.
   import {
     to = module.vpc.aws_vpc_ipv6_cidr_block_association.secondary["v4-ipv6"]
     id = var.v4_ipv6_association_id
   }
   ```

   `removed.from` addresses modules, not module instances: Terraform Core rejects `[0]` keys on `module.flow_logs` and `module.cloudwatch_log_group`. Omitting those two module instance keys matches all instances selected by the configuration; the indexed addresses remain valid for `terraform state show` and the IAM-role `moved` block.

   Declarative import requires Terraform >= 1.5; non-destructive `removed` requires Terraform >= 1.7. Therefore this ownership-preserving migration procedure has a Terraform >= 1.7 runner floor even though the v5 module itself remains compatible with Terraform >= 1.5. Keep the IAM role moved block active and preserve its exact `role_name_prefix`. The complete normal plan in section D evaluates the v5 configuration, all selected moves, three non-destructive forgets, the log-group import, and the optional IPv6 association import together; there is no preliminary state-materialization plan or CLI state surgery. The IPv6 import changes only Terraform ownership and must preserve zero destroy and zero replace.

### D. Complete-plan gate

9. Run and save a **complete normal plan**:

   ```shell
   terraform plan -out=v5-migration.tfplan
   terraform show -no-color v5-migration.tfplan > v5-migration.txt
   ```

   The gate criteria are:

   - **Required:** zero `destroy` and zero `replace` actions; no create/delete for VPC, subnets, route tables, NAT gateways/EIPs, gateways, attachments, CloudWatch log group, or IAM role; no destruction of S3 buckets or any log archive.
   - **Expected state-only transitions:** the selected `moved` pairs, three `removed { destroy = false }` forgets for the old log group/managed policy/attachment, one log-group import, and—when v4 IPv6 exists—one import of its existing association into `secondary["v4-ipv6"]`. Re-keyed routes whose destination is unchanged have no residual create/delete.
   - **Allowed creates:** `module.vpc.aws_iam_role_policy.flow_logs["default"]` for a module-created CloudWatch role, plus the expected built-in `terraform_data` precondition records. These records exist only in Terraform state and perform no AWS API operations. For the remediation-3 fixture the exact seven were:
     - `module.vpc.terraform_data.attachment_contract_validation`;
     - `module.vpc.terraform_data.cidrs_az_count_validation["private"]`;
     - `module.vpc.terraform_data.cidrs_az_count_validation["public"]`;
     - `module.vpc.terraform_data.cidrs_az_count_validation["workload"]`;
     - `module.vpc.terraform_data.nat_gateway_az_validation[0]`;
     - `module.vpc.terraform_data.nat_gateway_subnet_group_validation[0]`;
     - `module.vpc.terraform_data.vpc_ipv4_addressing_validation[0]`.
     Other configurations may select a different documented precondition subset; every address must correspond to a `terraform_data` block in the pinned module source.
   - **Expected IAM-role updates, when the v4 role was module-created:** the trust policy removes the legacy `Sid` and adds the desirable confused-deputy protections `aws:SourceAccount=<account-id>` and `aws:SourceArn=arn:<partition>:ec2:<region>:<account-id>:vpc-flow-log/*`; the description changes from `Cloudwatch permissions role for <vpc> with vpc-flow-logs` to `Allows VPC Flow Logs to publish <vpc>/default logs`. The role ID and generated name must remain unchanged.
   - **Other allowed in-place updates, only when explicitly reviewed:** Flow Log traffic type/log format/aggregation interval; CloudWatch retention and KMS key. With the migration Name formats, no Flow Log or log-group `Name` tag update is expected. Keep all other values identical unless the change is separately approved.
   - **Exceptional route residual:** delete/create is allowed only for a route destination deliberately changed during migration, enumerated by address and approved for a maintenance window. With frozen destinations the expected residual is zero.

   Any destroy, any replacement, any unlisted create/delete, or any unexpected `Name` update fails the gate.

### E. Ordered IAM permissions cutover and cleanup

10. Apply the saved complete plan. The v5 inline policy is created while the old managed policy and its attachment remain active in AWS because both were forgotten with `destroy = false`:

    ```shell
    terraform apply v5-migration.tfplan
    ```

11. Verify that `publish-vpc-flow-logs` exists inline on the preserved role and that the existing Flow Log continues delivering events newer than the apply to the preserved log group. Only after both checks pass, clean the two intentionally orphaned IAM artifacts using the complete role name and policy ARN captured in step 4:

    ```shell
    export V4_FLOW_LOG_ROLE_NAME='replace-with-generated-role-name'
    export V4_FLOW_LOG_POLICY_ARN='arn:aws:iam::123456789012:policy/replace-with-generated-policy-name'

    aws iam get-role-policy \
      --role-name "$V4_FLOW_LOG_ROLE_NAME" \
      --policy-name publish-vpc-flow-logs
    aws iam list-entities-for-policy \
      --policy-arn "$V4_FLOW_LOG_POLICY_ARN"
    aws iam detach-role-policy \
      --role-name "$V4_FLOW_LOG_ROLE_NAME" \
      --policy-arn "$V4_FLOW_LOG_POLICY_ARN"
    aws iam delete-policy \
      --policy-arn "$V4_FLOW_LOG_POLICY_ARN"
    ```

    The deliberate trade-off is two temporary AWS objects outside Terraform state: one managed policy (normally named from `<vpc>-cw-access-policy-`) and one attachment to the preserved role (normally named from `<vpc>-cw-access-role-`). This is preferable to a first plan containing premature destroys: Terraform cannot express a graph edge conditioned on successful post-apply log delivery. A temporary caller-managed copy of those resources was rejected because it duplicates provider configuration and state ownership without encoding that operational verification barrier. Record the cleanup output, then require a clean complete plan.

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

**Decision:** preserve the existing CloudWatch log group with one normal plan containing the v5 configuration, selected `moved` blocks, three `removed { destroy = false }` blocks for the old log group/managed policy/attachment, one log-group import, and the optional IPv6 association import. Preserve the IAM role with a moved block plus the exact v4 `name_prefix`. Apply the complete zero-destroy plan, verify the new inline policy and log delivery, then detach and delete the two temporarily orphaned IAM artifacts explicitly.

**Provider evidence:** in AWS provider 6.59.0, both `name` and `name_prefix` are `Optional + Computed + ForceNew` and conflict only when both are configured. Import uses the physical log-group name as the ID, and `resourceGroupRead`/`resourceGroupFlatten` writes the observed `name` **and** a derived `name_prefix`; import does not make `name_prefix` null. Because v5 configures the exact observed `name` and omits `name_prefix`, the latter remains provider-computed and does not itself force replacement. After a clean provider-6.x baseline refresh, a direct moved block can therefore also converge when the exact generated name is configured. The declarative remove/import form is preferred because the plan explicitly proves the ownership handoff at the final address and does not rely on the provenance of a legacy nested state snapshot. The previous statement that import worked by clearing `name_prefix` was incorrect.

**Rationale:** planning the forget and import in the same graph removes the procedural cycle exposed by two stateful rehearsals: the complete v5 configuration no longer evaluates before its destination exists at the v5 address. Terraform Core requires module addresses without instance keys in `removed.from`, so the nested `[0]` keys are intentionally omitted there. The IAM role uses `name_prefix` on both versions and moves without replacement. Forgetting the legacy managed policy and attachment prevents their premature deletion; Terraform cannot make deletion depend on successful post-apply log delivery, so explicit cleanup after verification is the only step outside the declarative state transition.

**Create-or-inject plan B:** callers that want the log group owned by a separate logging stack can set `create_destination = false` and inject its existing ARN through `destination_arn`; the VPC module then owns only the Flow Log. The old address must still be forgotten without destroy, and the external stack must already own the group. Terraform < 1.5 cannot run this v5 module at all; Terraform 1.5/1.6 can run the module but cannot express the non-destructive `removed` half of this same-plan handoff, so the migration runner must be upgraded to >= 1.7. After the cutover, remove the migration-only blocks and callers may return to any Terraform version supported by the module.

**Rejected default:** creating a new group (with create-before-destroy behavior or an accepted replacement) splits continuity at cutover. Historical logs remain in the old group only if that group is deliberately removed from Terraform ownership rather than destroyed; callers must then retain and eventually clean it up. This remains an opt-in maintenance-window fallback, not the migration default.

**Consequences:** one saved normal plan is both the state-transition proof and the migration gate. It includes selected moves, three non-destructive forgets, one log-group import, and the optional IPv6 association import; no refresh-only apply, `state rm`, or CLI import remains. The plan has zero destroys and zero replacements. Two IAM objects remain temporarily orphaned in AWS until delivery is verified and the documented `aws iam detach-role-policy` / `delete-policy` cleanup is executed.

## v4 Name formula mapping

| Resource | v4 formula | v5 migration setting | Result |
|---|---|---|---|
| VPC | `var.name` | `vpc.name = var.name` | Exact, unchanged. |
| Subnet | `${name_prefix || key}-${az}` | `subnets.<key>.name_prefix` copied; `name_format = "{group}-{az}"` | Exact for every reserved/private group. |
| Route table | `${name_prefix || key}-${az}` | Inherits the subnet `name_format`; leave `route_table_name_format` unset | Exact. Set the route-table field only if v4 was customized out of band. |
| NAT EIP | `nat-${public.name_prefix || "public"}-${az}` | `nat_gateway.subnet_group = "public"`; `name_format = "nat-{group}-{az}"`; leave `eip.name_format` unset | Exact. |
| NAT Gateway | `nat-${public.name_prefix || "public"}-${az}` | Same NAT format | Exact. |
| Internet Gateway | `${var.name}-igw` | `vpc.igw_name_format = "{vpc}-igw"` | Exact; also the v5 default. |
| Egress-only Internet Gateway | `var.name` | `vpc.eigw_name_format = "{vpc}"` | Exact; overrides the native v5 `"{vpc}-eigw"` default. |
| VPC Flow Log | `var.name` | `flow_logs.default.name_format = "{vpc}"` | Exact. |
| Generated CloudWatch log group | no `Name` tag | `flow_logs.default.cloudwatch_options.name_format = ""` | Exact; empty format removes caller `Name` keys. |

The default migration path therefore removes the 14 cosmetic updates observed in
the remediation-3 two-AZ fixture: six subnets, six route tables, one EIP, and one
NAT Gateway. As an explicit fallback, a team may omit the migration formats and
approve exactly those address-enumerated in-place `Name` tag updates as cosmetic;
that fallback must not broaden the allowlist to replacements or other tag changes.

## Variables

| v4 variable/path | v5 variable/path | Migration rule |
|---|---|---|
| `name` | `vpc.name` | Copy unchanged. |
| `create_vpc` + `vpc_id` | `vpc.create` + `vpc.id` | Create: keep `create=true` and `id=null`. Existing VPC: set `create=false` and `id`; the ID may be computed upstream. |
| `cidr_block` | `addressing.primary.cidr_block` | Primary CIDR when creating. For v4 secondary-CIDR mode, put it in a stable caller-owned entry such as `addressing.secondary.legacy.ipv4.cidr_block`. |
| `vpc_enable_dns_hostnames` | `vpc.dns.enable_hostnames` | Copy boolean. |
| `vpc_enable_dns_support` | `vpc.dns.enable_support` | Copy boolean. |
| `vpc_instance_tenancy` | `vpc.instance_tenancy` | Copy unchanged. |
| `vpc_ipv4_ipam_pool_id` | `addressing.primary.ipam_pool_id` | Copy with netmask length. |
| `vpc_ipv4_netmask_length` | `addressing.primary.netmask_length` | Convert the v4 string value to a number. |
| `vpc_assign_generated_ipv6_cidr_block` | `addressing.secondary.v4-ipv6.ipv6.amazon_assigned` | Copy as boolean and import the existing association ID as shown above. |
| `vpc_ipv6_cidr_block` | `addressing.secondary.v4-ipv6.ipv6.cidr_block` | Copy unchanged and import the existing association ID. |
| `vpc_ipv6_ipam_pool_id` | `addressing.secondary.v4-ipv6.ipv6.ipam_pool_id` | Copy with netmask length and import the existing association ID. |
| `vpc_ipv6_netmask_length` | `addressing.secondary.v4-ipv6.ipv6.netmask_length` | Convert the v4 string value to a number. |
| `vpc_secondary_cidr` | `addressing.secondary.<key>.ipv4` | Replace the boolean with a stable-keyed entry such as `legacy = { ipv4 = { cidr_block = ... } }`. v5 supports multiple named associations without positional state churn. |
| `vpc_secondary_cidr_natgw` | `nat_gateway.create=false` + `existing_ids` | Convert `{ az = { id = "nat-*" } }` to `{ az = "nat-*" }`; set inject mode plus matching NAT mode/AZ. |
| `az_count` | `availability_zones.count` | Development only. Explicit names are recommended for stable state. |
| `azs` | `availability_zones.names` | Copy unchanged; this is the production migration path. |
| `subnets.<key>.netmask` | `subnets.<key>.ipv4.netmask` | Add `role`; preserve `<key>`. Pin with `cidr_index` or, preferably, migrate with explicit current CIDRs. |
| `subnets.<key>.cidrs` | `subnets.<key>.ipv4.cidrs_by_az` | Build a map from each exact AZ name to its current state CIDR; order is irrelevant. |
| `subnets.<key>.assign_ipv6_cidr` | `subnets.<key>.ipv6.cidrs_by_az` + `auto_assign` + `secondary_cidr_key` | Read each existing `/64` from state, map it to its exact AZ name, set `auto_assign = true`, and select `"v4-ipv6"`. |
| `subnets.<key>.ipv6_cidrs` | `subnets.<key>.ipv6.cidrs_by_az` + `secondary_cidr_key` | Map exact prefixes by AZ name, select `"v4-ipv6"`, and set `auto_assign` to preserve address assignment behavior. |
| `subnets.<key>.ipv6_native` | `subnets.<key>.ipv6.native_only` + `secondary_cidr_key` | Set true, select `"v4-ipv6"`, and provide the existing IPv6 CIDRs keyed by AZ. |
| `subnets.<key>.assign_ipv6_address_on_creation` | `subnets.<key>.ipv6.auto_assign` | Copy boolean; v5 uses the typed IPv6 block. |
| `subnets.<key>.enable_resource_name_dns_aaaa_record_on_launch` | no direct v5 equivalent | Remove. This undocumented v4 private-group passthrough is not part of the v5 contract. |
| `subnets.<key>.name_prefix` | `subnets.<key>.name_prefix` | Copy unchanged; never rename the map key during the first migration. |
| v4 subnet/route-table Name formula | `subnets.<key>.name_format` | Set `"{group}-{az}"`; leave `route_table_name_format` unset so both reproduce v4. |
| v4 NAT/EIP Name formula | `nat_gateway.name_format` / `eip.name_format` | Set NAT to `"nat-{group}-{az}"`; EIP inherits it. |
| v4 IGW/EIGW Name formulas | `vpc.igw_name_format` / `vpc.eigw_name_format` | Set `"{vpc}-igw"` / `"{vpc}"`. |
| `subnets.<key>.tags` | `subnets.<key>.tags` | Copy unchanged. |
| implicit key class | `subnets.<key>.role` | `public` -> `public`; `transit_gateway` -> `transit_gateway`; `core_network` -> `core_network`; every other v4 key -> normally `private` (use `isolated` after removing Internet/NAT/transit routes; S3/DynamoDB gateway endpoint routes are allowed). |
| `subnets.public.connect_to_igw` | `subnets.public.routing.internet_gateway` | Copy boolean; null still defaults true for the public role. |
| `subnets.public.map_public_ip_on_launch` | `subnets.public.public_options.map_public_ip` | Copy boolean when true. Both v4 and v5 default to `false`, so omission preserves behavior. |
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
| v4 Flow Log `Name = var.name` | `flow_logs.default.name_format` | Set `"{vpc}"`; the v5 default includes the map key and would update the tag. |
| v4 generated log group without `Name` | `flow_logs.default.cloudwatch_options.name_format` | Set `""` to omit the tag independently from the Flow Log. |
| `vpc_flow_logs.name_override` or v4 generated log-group name | `flow_logs.default.cloudwatch_options.name` + declarative import ID | Set the exact physical `name` reported by `terraform state show`, not merely the old prefix. Use the root `removed { destroy=false }` + `import` handoff shown above. |
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
| `vpc_lattice.private_dns_enabled` | `vpc_lattice.private_dns_enabled` | Copy explicitly. When true, `dns_options.private_dns_preference` defaults to AWS's `VERIFIED_DOMAINS_ONLY`; choose a specified-domain mode and provide 1-10 domains only when required. DNS option changes replace the association. |
| `vpc_lattice.tags` | `vpc_lattice.tags` | Copy unchanged. |
| `optimize_subnet_cidr_ranges` | no direct equivalent | Removed. v5 uses explicit AZ-keyed CIDRs (recommended) or deterministic netmask allocation with optional `cidr_index`. |
| `tags` | `tags` | Copy unchanged. Keep provider `default_tags` unchanged; effective precedence is provider defaults < global tags < group/resource tags < generated Name. |

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

The active example contains 63 exact mappings for the union of a two-AZ representative state. It is a catalog, not a required move count. Select only sources present in `terraform state list`, repeat each per-AZ block for the real AZ set and each private group, and omit entire feature sections (TGW, Core Network, EIGW, Lattice, extra NAT AZs/routes) when absent. The remediation-3 state selected 26 applicable moves and omitted 37. Destination key suffixes use `replace(destination, "/", "-")` (for example `10.0.0.0/8` -> `10.0.0.0-8`). `aws_vpc.main[0]` and `aws_internet_gateway.main[0]` keep their address and need no block. The CloudWatch log group uses the ADR-F4-1 declarative forget/import handoff instead of a moved block.

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
  primary = { cidr_block = "10.42.0.0/16" }
  secondary = {
    legacy  = { ipv4 = { cidr_block = "100.64.0.0/16" } }
    v4-ipv6 = { ipv6 = { amazon_assigned = true } }
  }
}
```

A subnet that consumes this range sets `ipv4.secondary_cidr_key = "legacy"`;
that selector establishes the association dependency for a normal apply.

## Cases that cannot use `moved`

| v4 state | v5 disposition | Why / workaround |
|---|---|---|
| v4 IPv6 association embedded in `module.vpc.aws_vpc.main[0]` | `module.vpc.aws_vpc_ipv6_cidr_block_association.secondary["v4-ipv6"]` | Capture `ipv6_association_id` and declaratively import it at the standalone v5 address. An embedded VPC attribute cannot be the source of a `moved` block; this is state ownership transfer only and must plan zero destroy/zero replace. |
| `module.vpc.module.flow_logs[0].module.cloudwatch_log_group[0].aws_cloudwatch_log_group.main` | `module.vpc.aws_cloudwatch_log_group.flow_logs["default"]` | Capture the generated `name`, configure it as `cloudwatch_options.name`, forget the old address with `removed { destroy=false }`, and import that name at the v5 address in the same plan. A direct move can converge after provider-6.x refresh, but the declarative handoff makes ownership explicit and independently refreshes the final address. |
| `...aws_iam_role.main` | `module.vpc.aws_iam_role.flow_logs["default"]` | Keep the moved block, but first configure `role_name_prefix` with the exact v4 state `name_prefix`. Trust policy, description, and tags may update in place; the role ID and generated name must not change. |
| `module.vpc.module.flow_logs[0].module.cloudwatch_log_group[0].aws_iam_policy.main` | `module.vpc.aws_iam_role_policy.flow_logs["default"]` | Resource type changes, so forget the v4 managed policy with the unindexed-module `removed { destroy=false }` address. After the zero-destroy apply and delivery verification, delete the captured policy ARN with the documented AWS CLI cleanup. |
| `...aws_iam_role_policy_attachment.main` | no v5 resource | Forget the attachment with `removed { destroy=false }`; after verifying the inline policy and new log events, detach the captured policy ARN from the preserved generated role, then delete the policy. |
| v4-created S3 Flow Log bucket and its public-access, encryption, and lifecycle resources | caller-owned logging module/resource | v5 intentionally does not own durable S3/Firehose destinations. Move same-type resources with `terraform state mv` into a new caller-owned logging resource/module address, or import them there, then pass the bucket ARN as `flow_logs.default.destination_arn`. Do not allow Terraform to destroy a log archive. |
| Any address whose destination is an injected ID (`vpc.create=false`, `vpc.igw_create=false`, `nat_gateway.create=false`, `subnets[*].manage_route_table=false`) | no managed destination resource | Injection removes lifecycle ownership; the paired ID fields may be computed. First establish ownership in the destination configuration, then use a declarative `removed { destroy=false }` handoff so the normal plan proves that the physical object is retained. |
| Route whose v4 destination or v5 route list changed during migration | no safe one-to-one block | Freeze destinations for the migration. If already changed, import the AWS route into the final v5 address where supported, or allow a reviewed delete/create during a maintenance window. |

`terraform state mv` is appropriate only when source and destination have the same resource type. Prefer declarative `moved` blocks for repeatability and retain them until every workspace has applied the upgrade.
