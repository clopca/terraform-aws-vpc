<!-- BEGIN_TF_DOCS -->
# AWS VPC module v5 — typed subnet contract

> **Pre-release v5 module.** The v4 module remains at the repository root. This
> directory contains the typed v5 contract and requires Terraform `>= 1.5` plus
> AWS provider `>= 6.29`.

v5 replaces heterogeneous subnet maps with typed subnet groups, stable
`"<group>/<az>"` resource keys, explicit semantic roles, create-or-inject
boundaries, native Flow Logs, and tiered outputs.

## Usage

Use explicit AZ names and CIDRs for production. The following creates two public
and two private subnets and one public NAT Gateway in `us-east-1a`:

```hcl
module "vpc" {
  source = "./v5"

  vpc = {
    name = "application-vpc"
  }

  addressing = {
    ipv4 = { cidr_block = "10.20.0.0/16" }
  }

  availability_zones = {
    names = ["us-east-1a", "us-east-1b"]
  }

  subnets = {
    public = {
      role = "public"
      ipv4 = { cidrs = ["10.20.0.0/24", "10.20.1.0/24"] }
    }

    app = {
      role = "private"
      ipv4 = { cidrs = ["10.20.10.0/24", "10.20.11.0/24"] }
      routing = {
        nat_gateway = true
      }
    }
  }

  nat_gateway = {
    mode         = "single_az"
    az           = "us-east-1a"
    subnet_group = "public"
  }
}
```

Complete configurations are available in [`examples/basic`](examples/basic),
[`examples/enterprise`](examples/enterprise), and [`examples/hub`](examples/hub).

## Address stability

Subnet group keys are state identity. Renaming a group changes every
`aws_subnet.main["<group>/<az>"]` address and requires explicit `moved` blocks.
Use `name_prefix` for cosmetic changes.

IPv4 allocation has three modes:

1. **Explicit `cidrs`** — passed through unchanged and recommended for production.
2. **IPAM** — AWS allocates the subnet CIDR from the supplied pool and netmask.
3. **Calculated `netmask`** — deterministic convenience allocation. Each group
   reserves six AZ slots, so appending an AZ does not move existing CIDRs.
   `cidr_index` pins an absolute group slot; unpinned groups are packed after all
   pinned slots by netmask and group name. Adding or removing an unpinned group
   can move later unpinned groups.

## Output guarantees

- **Tier 1 — stable handles:** IDs, CIDRs, ARNs, and maps by group, semantic role,
  and AZ. Names, value shapes, and existing keys are semver-protected; minor
  releases may add outputs or map keys.
- **Tier 2 — v4 compatibility:** deprecated full-object aliases preserve v4
  names and outer keys during v5. They are removed in v6. Keep migrated reserved
  group names (`public`, `transit_gateway`, `core_network`) and Flow Log key
  `default` for exact compatibility.
- **Tier 3 — escape hatch:** `resources` exposes complete provider objects and has
  no semver guarantee.

Prefer Tier 1 for every new consumer. Tier 2 exists only to migrate existing v4
dependencies; Tier 3 is for provider attributes not represented by a stable handle.

## Migration from v4

Follow the normative [v4 to v5 migration runbook](../docs/rfc/v5-migration.md).
It includes the input/output mapping, 63 representative `moved` blocks, the
CloudWatch log-group remove/import exception, a zero-replacement plan allowlist,
and post-apply physical-ID checks. Always test the procedure against a copy of
state and keep the caller-owned `moved.tf` until every workspace has upgraded.

## Native tests

The test suite uses Terraform mock providers and does not require AWS credentials.
Module tests are plan-only. The migration fixture performs one apply against the
mock provider solely to seed ephemeral test state, then verifies the v4-to-v5
moves with a plan. Run:

```shell
terraform init -backend=false
terraform test
terraform fmt -check -recursive .
terraform validate
```

Mock providers require Terraform `>= 1.7` when running tests.

## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.29 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.29 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ec2_transit_gateway_vpc_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_vpc_attachment) | resource |
| [aws_egress_only_internet_gateway.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/egress_only_internet_gateway) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_internet_gateway.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_networkmanager_attachment_accepter.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkmanager_attachment_accepter) | resource |
| [aws_networkmanager_vpc_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkmanager_vpc_attachment) | resource |
| [aws_route.cwan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.cwan_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.eigw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.igw_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.igw_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.nat64](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.tgw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.tgw_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_subnet.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_ipv4_cidr_block_association.secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_ipv4_cidr_block_association) | resource |
| [aws_vpclattice_service_network_vpc_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpclattice_service_network_vpc_association) | resource |
| [terraform_data.attachment_contract_validation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.cidr_pinning_validation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.cidrs_az_count_validation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.dns64_requires_nat_gateway](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.eigw_requires_ipv6](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.injected_route_table_all_az_nat_validation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.ipv6_cidrs_az_count_validation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.nat_gateway_az_validation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.nat_gateway_eip_allocation_ids_validation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.nat_gateway_existing_ids_validation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.nat_gateway_subnet_group_validation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.nat_routing_requires_nat_gateway](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.vpc_ipv4_addressing_validation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_availability_zones.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_vpc.existing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_addressing"></a> [addressing](#input\_addressing) | IPv4 and/or IPv6 addressing for the VPC. Supports static CIDR, IPAM, or<br/>Amazon-assigned IPv6. At least one of ipv4 or ipv6 must be configured.<br/>For IPAM: provide ipam\_pool\_id + netmask\_length (mutually exclusive with cidr\_block). | <pre>object({<br/>    ipv4 = optional(object({<br/>      cidr_block     = optional(string)<br/>      ipam_pool_id   = optional(string)<br/>      netmask_length = optional(number)<br/>      secondary = optional(list(object({<br/>        cidr_block     = optional(string)<br/>        ipam_pool_id   = optional(string)<br/>        netmask_length = optional(number)<br/>      })), [])<br/>    }))<br/>    ipv6 = optional(object({<br/>      amazon_assigned = optional(bool, false)<br/>      cidr_block      = optional(string)<br/>      ipam_pool_id    = optional(string)<br/>      netmask_length  = optional(number)<br/>    }))<br/>  })</pre> | n/a | yes |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | AZ selection. Provide either an explicit list of AZ names or a count<br/>(takes first N from the region alphabetically). Exactly one is required.<br/><br/>⚠️  `count` mode is for DEVELOPMENT ONLY. For production, always use explicit<br/>`names` to guarantee AZ stability. Because `count` resolves AZ names through an<br/>AWS data source, preconditions that depend on the resolved AZ set are unknown<br/>during the initial plan and are deferred by Terraform to apply time. | <pre>object({<br/>    names = optional(list(string))<br/>    count = optional(number)<br/>  })</pre> | n/a | yes |
| <a name="input_vpc"></a> [vpc](#input\_vpc) | VPC configuration. Set `id` to reference an existing VPC instead of creating one.<br/>When `id` is set, the module manages subnets/routes within that VPC but does not<br/>create or modify the VPC resource itself.<br/><br/>Set `igw_id` to reference an existing Internet Gateway instead of creating one<br/>(create-or-inject pattern for IGW). [R1-H2] | <pre>object({<br/>    name             = string<br/>    id               = optional(string) # null = create new VPC; set = inject existing<br/>    igw_id           = optional(string) # null = create IGW if needed; set = use existing [R1-H2]<br/>    instance_tenancy = optional(string, "default")<br/>    dns = optional(object({<br/>      enable_hostnames = optional(bool, true)<br/>      enable_support   = optional(bool, true)<br/>    }), {})<br/>    tags = optional(map(string), {})<br/>  })</pre> | n/a | yes |
| <a name="input_flow_logs"></a> [flow\_logs](#input\_flow\_logs) | VPC Flow Logs keyed by a stable logical name. Map keys are Terraform state<br/>identity and must not be renamed without a moved block.<br/><br/>destination\_type accepts cloudwatch, s3, or kinesis (Kinesis Data Firehose).<br/>CloudWatch supports create-or-inject for both the log group and the VPC Flow<br/>Logs IAM role. `cloudwatch_options.name` is the fixed physical log-group name;<br/>set it to the exact imported v4 name during migration. `role_name_prefix` is<br/>passed through exactly (maximum 38 characters) so a moved v4 IAM role keeps its<br/>original prefix and is not replaced. S3 buckets and Firehose delivery streams<br/>are external resources: destination\_arn is required so their lifecycle, KMS,<br/>retention, and ownership policies remain outside this VPC module.<br/><br/>Migration note: `cloudwatch_options.name` preserves the physical name only when<br/>the v4 log group is removed from its old state address and imported at the v5<br/>address. A moved block from v4 `name_prefix` to v5 `name` is replacement-prone. | <pre>map(object({<br/>    enabled                        = optional(bool, true)<br/>    destination_type               = optional(string, "cloudwatch")<br/>    destination_arn                = optional(string)<br/>    iam_role_arn                   = optional(string)<br/>    deliver_cross_account_role_arn = optional(string)<br/>    traffic_type                   = optional(string, "ALL")<br/>    log_format                     = optional(string)<br/>    max_aggregation_interval       = optional(number, 600)<br/>    role_name_prefix               = optional(string)<br/>    role_permissions_boundary      = optional(string)<br/>    cloudwatch_options = optional(object({<br/>      name              = optional(string)<br/>      retention_in_days = optional(number, 30)<br/>      kms_key_id        = optional(string)<br/>    }), {})<br/>    s3_options = optional(object({<br/>      file_format                = optional(string, "plain-text")<br/>      hive_compatible_partitions = optional(bool, false)<br/>      per_hour_partition         = optional(bool, false)<br/>    }), {})<br/>    tags = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_nat_gateway"></a> [nat\_gateway](#input\_nat\_gateway) | NAT Gateway configuration. Controls how many NAT GWs are created and how<br/>their Elastic IPs are sourced (create new, use BYOIP pool, or inject existing).<br/>The `az` field is REQUIRED when mode = "single\_az" to avoid positional fragility.<br/><br/>Set `existing_ids` to inject existing NAT Gateways (create-or-inject pattern).<br/>When set, the module uses the referenced NAT GWs instead of creating new ones.<br/><br/>`connectivity_type` controls whether the NAT is public (internet-facing, needs EIP)<br/>or private (inter-VPC, no EIP). Default: "public".<br/><br/>`subnet_group` explicitly selects the subnet group that hosts created NAT<br/>Gateways. It must reference a public group for public NAT or a private group<br/>for private NAT. Default null preserves convenience behavior by selecting the<br/>first compatible group alphabetically; set it explicitly in production so<br/>adding another group cannot relocate the NAT Gateway. | <pre>object({<br/>    mode              = optional(string, "none")<br/>    az                = optional(string)<br/>    connectivity_type = optional(string, "public") # "public" | "private"<br/>    subnet_group      = optional(string)           # explicit NAT host group; null = first compatible group<br/>    existing_ids      = optional(map(string))      # az → nat_gateway_id, for inject mode [R1-H2]<br/>    eip = optional(object({<br/>      mode             = optional(string, "create")<br/>      public_ipv4_pool = optional(string)<br/>      allocation_ids   = optional(map(string)) # R2-H2: default null instead of {}<br/>    }), { mode = "create" })<br/>  })</pre> | <pre>{<br/>  "mode": "none"<br/>}</pre> | no |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | Map of subnet groups. Each key is a stable logical name (used in state keys<br/>as "key/az"). Keys are IMMUTABLE post-deploy — renaming requires `moved` blocks.<br/><br/>The `role` field determines creation behavior:<br/>  - public:          gets IGW route, optional NAT gateway hosting<br/>  - private:         standard private subnet, optional NAT/EIGW routing<br/>  - isolated:        no outbound routing (databases, internal-only)<br/>  - transit\_gateway: dedicated small subnets for TGW ENIs<br/>  - core\_network:    dedicated small subnets for Cloud WAN attachments<br/><br/>Multiple subnet groups per role are allowed:<br/>  - public: N groups allowed (e.g. DMZ, edge, GWLB) [R1-C1]<br/>  - transit\_gateway: limited to 1 group (AWS API: 1 VPC attachment per TGW per VPC)<br/>    NOTE: if AWS adds multi-attachment support, this constraint will be relaxed<br/>    as a non-breaking change.<br/>  - core\_network: limited to 1 group (same AWS API constraint)<br/><br/>Set `route_table_id` to inject one existing route table for the whole subnet<br/>group. The module will not create route tables for that group; it associates<br/>every AZ subnet with the injected table and adds all routes declared in<br/>`routing` to it. A shared injected table cannot provide per-AZ NAT targets, so<br/>`nat_gateway.mode = "all_azs"` is rejected when that group requests NAT/NAT64. | <pre>map(object({<br/>    role = string<br/><br/>    # ── IPv4 Addressing (one of netmask/cidrs/ipam required unless ipv6 native_only) ──<br/>    ipv4 = optional(object({<br/>      netmask        = optional(number)<br/>      cidrs          = optional(list(string))<br/>      ipam_pool_id   = optional(string)<br/>      netmask_length = optional(number)<br/>      # Absolute CIDR group slot for pinning [R1-C2]. Each slot reserves six<br/>      # AZ-sized CIDRs at this netmask. Pinned ranges never move when groups or AZs<br/>      # are added/removed; overlapping pins across netmasks are rejected.<br/>      cidr_index = optional(number)<br/>    }))<br/><br/>    # ── IPv6 Addressing ──<br/>    ipv6 = optional(object({<br/>      auto_assign = optional(bool, false)<br/>      cidrs       = optional(list(string))<br/>      native_only = optional(bool, false)<br/>    }))<br/><br/>    # ── Naming, Tags, and Route Table Injection ──<br/>    name_prefix    = optional(string)<br/>    tags           = optional(map(string), {})<br/>    route_table_id = optional(string) # one existing shared RT for all AZs in this group<br/><br/>    # ── Routing (co-located per subnet group) ──<br/>    # [R1-C3]: transit_gateway and core_network accept lists of destinations<br/>    # to support multiple routes (e.g. 10.0.0.0/8 + 172.16.0.0/12 → TGW).<br/>    # [R2-H3]: internet_gateway defaults to null; auto-resolved as true for<br/>    # role="public", false otherwise. Set explicitly to override.<br/>    routing = optional(object({<br/>      nat_gateway          = optional(bool, false)<br/>      egress_only_igw      = optional(bool, false)<br/>      internet_gateway     = optional(bool)         # null = auto (true for public, false otherwise)<br/>      dns64                = optional(bool, false)  # Also creates 64:ff9b::/96 -> NAT GW; requires NAT<br/>      transit_gateway      = optional(list(string)) # list of CIDRs/prefix-list IDs to route via TGW [R1-C3]<br/>      transit_gateway_ipv6 = optional(list(string)) # list of IPv6 CIDRs/prefix-list IDs [R1-C3]<br/>      core_network         = optional(list(string)) # list of CIDRs/prefix-list IDs to route via CWAN [R1-C3]<br/>      core_network_ipv6    = optional(list(string)) # list of IPv6 CIDRs/prefix-list IDs [R1-C3]<br/>    }), {})<br/><br/>    # ── Public role options ──<br/>    public_options = optional(object({<br/>      map_public_ip = optional(bool, true)<br/>    }))<br/><br/>    # ── Transit Gateway attachment options ──<br/>    transit_gateway_options = optional(object({<br/>      id                              = string<br/>      default_route_table_association = optional(bool, true)<br/>      default_route_table_propagation = optional(bool, true)<br/>      appliance_mode_support          = optional(bool, false)<br/>      dns_support                     = optional(bool, true)<br/>      security_group_referencing      = optional(bool, true) # Requires provider >= 5.69<br/>    }))<br/><br/>    # ── Core Network (Cloud WAN) attachment options ──<br/>    core_network_options = optional(object({<br/>      id                 = string<br/>      arn                = optional(string) # Optional: auto-derived from id if omitted<br/>      appliance_mode     = optional(bool, false)<br/>      require_acceptance = optional(bool, false)<br/>      accept_attachment  = optional(bool, false)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to all resources created by this module. | `map(string)` | `{}` | no |
| <a name="input_vpc_lattice"></a> [vpc\_lattice](#input\_vpc\_lattice) | VPC Lattice Service Network association. Null disables the association. | <pre>object({<br/>    service_network_identifier = string<br/>    security_group_ids         = optional(set(string), [])<br/>    private_dns_enabled        = optional(bool, false)<br/>    tags                       = optional(map(string), {})<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_azs"></a> [azs](#output\_azs) | List of Availability Zones where subnets were created. |
| <a name="output_core_network_attachment"></a> [core\_network\_attachment](#output\_core\_network\_attachment) | DEPRECATED: v4-compatible full Cloud WAN attachment object. Use core\_network\_attachment\_id. Removed in v6. |
| <a name="output_core_network_attachment_id"></a> [core\_network\_attachment\_id](#output\_core\_network\_attachment\_id) | Cloud WAN Core Network VPC attachment ID, or null when the role is absent. |
| <a name="output_core_network_subnet_attributes_by_az"></a> [core\_network\_subnet\_attributes\_by\_az](#output\_core\_network\_subnet\_attributes\_by\_az) | DEPRECATED: v4-compatible map of full Cloud WAN subnet objects keyed by AZ. Use Tier 1 subnet outputs. Removed in v6. |
| <a name="output_egress_only_igw_id"></a> [egress\_only\_igw\_id](#output\_egress\_only\_igw\_id) | Egress-only Internet Gateway ID, or null when not created. |
| <a name="output_egress_only_internet_gateway"></a> [egress\_only\_internet\_gateway](#output\_egress\_only\_internet\_gateway) | DEPRECATED: v4-compatible full Egress-only Internet Gateway object. Use egress\_only\_igw\_id. Removed in v6. |
| <a name="output_flow_log_attributes"></a> [flow\_log\_attributes](#output\_flow\_log\_attributes) | DEPRECATED: v4-compatible single full Flow Log object. Uses key 'default', or the only configured Flow Log. Use flow\_log\_ids. Removed in v6. |
| <a name="output_flow_log_destination_arns"></a> [flow\_log\_destination\_arns](#output\_flow\_log\_destination\_arns) | VPC Flow Log destination ARNs by stable flow\_logs map key. |
| <a name="output_flow_log_ids"></a> [flow\_log\_ids](#output\_flow\_log\_ids) | VPC Flow Log IDs by the stable flow\_logs map key. Shape: map(key, flow\_log\_id). |
| <a name="output_flow_log_role_arns"></a> [flow\_log\_role\_arns](#output\_flow\_log\_role\_arns) | CloudWatch delivery role ARNs by flow-log key; null for S3 and Firehose. |
| <a name="output_internet_gateway"></a> [internet\_gateway](#output\_internet\_gateway) | DEPRECATED: v4-compatible full created Internet Gateway object. Use internet\_gateway\_id. Removed in v6. |
| <a name="output_internet_gateway_id"></a> [internet\_gateway\_id](#output\_internet\_gateway\_id) | Internet Gateway ID (created or injected), or null when no IGW is needed. |
| <a name="output_nat_eip_allocation_ids"></a> [nat\_eip\_allocation\_ids](#output\_nat\_eip\_allocation\_ids) | Created or caller-supplied EIP allocation IDs by AZ for public NAT Gateways. Empty for injected/private NAT Gateways. |
| <a name="output_nat_gateway_attributes_by_az"></a> [nat\_gateway\_attributes\_by\_az](#output\_nat\_gateway\_attributes\_by\_az) | DEPRECATED: v4-compatible map of full created NAT Gateway objects keyed by AZ. Use nat\_gateway\_ids/nat\_*\_ips. Removed in v6. |
| <a name="output_nat_gateway_ids"></a> [nat\_gateway\_ids](#output\_nat\_gateway\_ids) | NAT Gateway IDs by AZ. Empty when nat\_gateway.mode is none. Shape: map(az, nat\_gateway\_id). |
| <a name="output_nat_private_ips"></a> [nat\_private\_ips](#output\_nat\_private\_ips) | Created NAT Gateway private IPs by AZ. Empty when NAT Gateways are injected. |
| <a name="output_nat_public_ips"></a> [nat\_public\_ips](#output\_nat\_public\_ips) | Created public NAT Gateway public IPs by AZ. Empty for injected or private NAT Gateways. |
| <a name="output_natgw_id_per_az"></a> [natgw\_id\_per\_az](#output\_natgw\_id\_per\_az) | DEPRECATED: v4-compatible map(az, object({id=string})); duplicates the selected ID in single\_az mode. Use nat\_gateway\_ids. Removed in v6. |
| <a name="output_private_subnet_attributes_by_az"></a> [private\_subnet\_attributes\_by\_az](#output\_private\_subnet\_attributes\_by\_az) | DEPRECATED: v4-compatible map of full private subnet objects keyed '<group>/<az>'. Use Tier 1 subnet outputs. Removed in v6. |
| <a name="output_public_subnet_attributes_by_az"></a> [public\_subnet\_attributes\_by\_az](#output\_public\_subnet\_attributes\_by\_az) | DEPRECATED: v4-compatible map of full public subnet objects keyed by AZ. Use Tier 1 subnet outputs. Removed in v6. |
| <a name="output_resources"></a> [resources](#output\_resources) | UNSTABLE: complete internal resource objects for advanced composition. Shape may change in any release; prefer Tier 1. |
| <a name="output_route_table_ids_by_group"></a> [route\_table\_ids\_by\_group](#output\_route\_table\_ids\_by\_group) | Route table IDs by subnet group. Shape: map(group\_name, list(route\_table\_id)). |
| <a name="output_route_table_ids_by_group_by_az"></a> [route\_table\_ids\_by\_group\_by\_az](#output\_route\_table\_ids\_by\_group\_by\_az) | Route table IDs by subnet group and AZ. Shape: map(group\_name, map(az, route\_table\_id)). |
| <a name="output_route_table_ids_by_semantic_role"></a> [route\_table\_ids\_by\_semantic\_role](#output\_route\_table\_ids\_by\_semantic\_role) | Route table IDs by semantic role. Shape: map(role, list(route\_table\_id)). |
| <a name="output_route_table_ids_by_semantic_role_by_az"></a> [route\_table\_ids\_by\_semantic\_role\_by\_az](#output\_route\_table\_ids\_by\_semantic\_role\_by\_az) | Route table IDs by semantic role and AZ. Shape: map(role, map(az, list(route\_table\_id))). |
| <a name="output_rt_attributes_by_type_by_az"></a> [rt\_attributes\_by\_type\_by\_az](#output\_rt\_attributes\_by\_type\_by\_az) | DEPRECATED: v4-compatible full route-table objects keyed type then AZ or '<group>/<az>' for private. Use Tier 1 route table IDs. Removed in v6. |
| <a name="output_subnet_arns_by_group_by_az"></a> [subnet\_arns\_by\_group\_by\_az](#output\_subnet\_arns\_by\_group\_by\_az) | Subnet ARNs by group and AZ. Shape: map(group\_name, map(az, arn)). |
| <a name="output_subnet_cidrs_by_group"></a> [subnet\_cidrs\_by\_group](#output\_subnet\_cidrs\_by\_group) | Subnet IPv4 CIDRs by group. Shape: map(group\_name, list(cidr\|null)). |
| <a name="output_subnet_cidrs_by_group_by_az"></a> [subnet\_cidrs\_by\_group\_by\_az](#output\_subnet\_cidrs\_by\_group\_by\_az) | Subnet IPv4 CIDRs by group and AZ. Shape: map(group\_name, map(az, cidr\|null)). |
| <a name="output_subnet_cidrs_by_role_by_az"></a> [subnet\_cidrs\_by\_role\_by\_az](#output\_subnet\_cidrs\_by\_role\_by\_az) | DEPRECATED: prototype alias keyed by group name. Use subnet\_cidrs\_by\_group\_by\_az. Removed in v6. |
| <a name="output_subnet_cidrs_by_semantic_role"></a> [subnet\_cidrs\_by\_semantic\_role](#output\_subnet\_cidrs\_by\_semantic\_role) | Subnet IPv4 CIDRs by semantic role. Shape: map(role, list(cidr\|null)). |
| <a name="output_subnet_cidrs_by_semantic_role_by_az"></a> [subnet\_cidrs\_by\_semantic\_role\_by\_az](#output\_subnet\_cidrs\_by\_semantic\_role\_by\_az) | Subnet IPv4 CIDRs by semantic role and AZ. Shape: map(role, map(az, list(cidr\|null))). |
| <a name="output_subnet_ids_by_group"></a> [subnet\_ids\_by\_group](#output\_subnet\_ids\_by\_group) | Subnet IDs by group. Shape: map(group\_name, list(subnet\_id)). |
| <a name="output_subnet_ids_by_group_by_az"></a> [subnet\_ids\_by\_group\_by\_az](#output\_subnet\_ids\_by\_group\_by\_az) | Subnet IDs by group and AZ. Shape: map(group\_name, map(az, subnet\_id)). |
| <a name="output_subnet_ids_by_role"></a> [subnet\_ids\_by\_role](#output\_subnet\_ids\_by\_role) | DEPRECATED: prototype alias keyed by group name. Use subnet\_ids\_by\_group. Removed in v6. |
| <a name="output_subnet_ids_by_role_by_az"></a> [subnet\_ids\_by\_role\_by\_az](#output\_subnet\_ids\_by\_role\_by\_az) | DEPRECATED: prototype alias keyed by group name. Use subnet\_ids\_by\_group\_by\_az. Removed in v6. |
| <a name="output_subnet_ids_by_semantic_role"></a> [subnet\_ids\_by\_semantic\_role](#output\_subnet\_ids\_by\_semantic\_role) | Subnet IDs by semantic role. Shape: map(role, list(subnet\_id)). |
| <a name="output_subnet_ids_by_semantic_role_by_az"></a> [subnet\_ids\_by\_semantic\_role\_by\_az](#output\_subnet\_ids\_by\_semantic\_role\_by\_az) | Subnet IDs by semantic role and AZ. Shape: map(role, map(az, list(subnet\_id))). |
| <a name="output_tgw_subnet_attributes_by_az"></a> [tgw\_subnet\_attributes\_by\_az](#output\_tgw\_subnet\_attributes\_by\_az) | DEPRECATED: v4-compatible map of full TGW subnet objects keyed by AZ. Use Tier 1 subnet outputs. Removed in v6. |
| <a name="output_transit_gateway_attachment_id"></a> [transit\_gateway\_attachment\_id](#output\_transit\_gateway\_attachment\_id) | Transit Gateway VPC attachment ID, or null when the role is absent. |
| <a name="output_vpc_arn"></a> [vpc\_arn](#output\_vpc\_arn) | The ARN of the VPC (created or referenced). |
| <a name="output_vpc_attributes"></a> [vpc\_attributes](#output\_vpc\_attributes) | DEPRECATED: v4-compatible full VPC object. Use vpc\_id/vpc\_arn/vpc\_cidr\_block. Removed in v6. |
| <a name="output_vpc_cidr_block"></a> [vpc\_cidr\_block](#output\_vpc\_cidr\_block) | The primary IPv4 CIDR block of the VPC. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | The ID of the VPC (created or referenced). |
| <a name="output_vpc_lattice_service_network_association"></a> [vpc\_lattice\_service\_network\_association](#output\_vpc\_lattice\_service\_network\_association) | DEPRECATED: v4-compatible full VPC Lattice association object. Use vpc\_lattice\_service\_network\_association\_id. Removed in v6. |
| <a name="output_vpc_lattice_service_network_association_id"></a> [vpc\_lattice\_service\_network\_association\_id](#output\_vpc\_lattice\_service\_network\_association\_id) | VPC Lattice Service Network VPC association ID, or null when disabled. |
<!-- END_TF_DOCS -->