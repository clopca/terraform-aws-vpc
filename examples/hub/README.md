# Multi-fabric network hub

This example creates a three-AZ dual-stack hub connected to two Transit Gateways and one Cloud WAN Core Network, plus a separate two-AZ inspection VPC with private NAT. Use it for advanced routing compositions that need stable attachment identities, explicit acceptance ownership, existing public addresses, and externally managed flow-log delivery.

## What this demonstrates

- Caller-owned `east` and `west` keys independently identify two TGW attachments and their selected route destinations.
- A `core_network` subnet group creates a Cloud WAN attachment and explicitly accepts it after AWS reports it pending.
- Generic typed routes target an existing VPC peering connection without changing the attachment model.
- Existing Elastic IPs are injected into three public NAT Gateways and remain caller-owned.
- A second VPC demonstrates private NAT between firewall and TGW attachment subnets.

## Relevant configuration

The complete configuration is in [`main.tf`](./main.tf). The fabric attachment declarations are the scenario-specific portion:

```hcl
subnets = {
  cwan = {
    role = "core_network"
    ipv4 = {
      netmask    = 28
      cidr_index = 65
    }
    ipv6 = {
      secondary_cidr_key = "amazon-ipv6"
      auto_assign        = true
      cidr_index         = 4
    }
    core_network_options = {
      id                 = var.core_network_id
      arn                = var.core_network_arn
      appliance_mode     = false
      require_acceptance = true
      accept_attachment  = true
    }
  }
}

transit_gateway_attachments = {
  east = {
    subnet_group                    = "tgw"
    id                              = var.transit_gateway_ids["east"]
    default_route_table_association = false
    default_route_table_propagation = false
    appliance_mode_support          = true
    dns_support                     = true
    security_group_referencing      = true
  }
  west = {
    subnet_group                    = "tgw"
    id                              = var.transit_gateway_ids["west"]
    default_route_table_association = false
    default_route_table_propagation = false
    appliance_mode_support          = true
    dns_support                     = true
    security_group_referencing      = true
  }
}
```

## Prerequisites and cost

- Terraform `>= 1.5` and AWS provider `>= 6.29`.
- AWS credentials with VPC, TGW attachment, Cloud WAN attachment and acceptance, NAT Gateway, Elastic IP association, and flow-log permissions.
- Two distinct Transit Gateways, an existing Cloud WAN Core Network, an existing VPC peering connection, three unassociated Elastic IPs, and an existing Firehose delivery stream.
- The Core Network policy must permit this VPC attachment, and the executing identity must own the acceptance action selected by `accept_attachment = true`.
- **Cost:** five NAT Gateways, three public IPv4 addresses, three TGW attachments, one Cloud WAN attachment, flow-log delivery, processing, and cross-AZ or inter-Region transfer can incur charges.

## Run

Create `hub.tfvars` with the real external identifiers:

```hcl
transit_gateway_ids = {
  east = "tgw-0123456789abcdef0"
  west = "tgw-1123456789abcdef0"
}
vpc_peering_connection_id = "pcx-0123456789abcdef0"
core_network_id            = "cnet-0123456789abcdef0"
core_network_arn           = "arn:aws:networkmanager::123456789012:core-network/cnet-0123456789abcdef0"
nat_eip_allocation_ids = {
  "us-west-2a" = "eipalloc-0123456789abcdef0"
  "us-west-2b" = "eipalloc-1123456789abcdef0"
  "us-west-2c" = "eipalloc-2123456789abcdef0"
}
flow_log_destination_arn = "arn:aws:firehose:us-west-2:123456789012:deliverystream/vpc-flow-logs"
```

```shell
terraform init
terraform validate
terraform plan -out=tfplan -var-file=hub.tfvars
terraform apply tfplan
terraform output transit_gateway_attachment_ids
terraform output core_network_attachment_id
terraform destroy -var-file=hub.tfvars
```

A successful apply returns separate TGW attachment IDs under `east` and `west`; changing either key changes Terraform state identity, so preserve these keys when only an external gateway ID changes.
