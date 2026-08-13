# Enterprise VPC with shared-services addressing

This example creates a three-AZ production VPC with explicit IPv4 ranges, dual-stack application subnets, isolated data and endpoint tiers, zonal NAT Gateways, flow logs, and a VPC Lattice association. Use it when address ownership, compliance tagging, service-network connectivity, and per-AZ egress must be declared together.

## What this demonstrates

- Explicit CIDRs preserve subnet identity across the selected Availability Zones.
- A named secondary IPv4 association isolates the endpoint address space from the primary VPC range.
- Application subnets use dual-stack egress while data and endpoint subnets remain isolated.
- `all_azs` NAT provides an AZ-local IPv4 egress path for every application subnet.
- A module-owned flow-log destination and a caller-created VPC Lattice service network are composed in one configuration.

## Relevant configuration

The complete configuration is in [`main.tf`](./main.tf). The shared-services subnet, NAT topology, and Lattice association are the distinguishing declarations:

```hcl
subnets = {
  endpoints = {
    role = "isolated"
    ipv4 = {
      cidrs_by_az = {
        "eu-west-1a" = "100.64.0.0/26"
        "eu-west-1b" = "100.64.0.64/26"
        "eu-west-1c" = "100.64.0.128/26"
      }
      secondary_cidr_key = "shared-services"
    }
    tags = { Tier = "vpc-endpoints" }
  }
}

nat_gateway = {
  mode         = "all_azs"
  subnet_group = "public"
}

vpc_lattice = {
  enabled                    = true
  service_network_identifier = aws_vpclattice_service_network.enterprise.id
  private_dns_enabled        = true
  tags                       = { Tier = "service-network" }
}
```

## Prerequisites and cost

- Terraform `>= 1.5` and AWS provider `>= 6.29`.
- AWS credentials with permissions for VPC networking, Elastic IPs, CloudWatch Logs, IAM, and VPC Lattice service networks and associations.
- The explicit `eu-west-1a`, `eu-west-1b`, and `eu-west-1c` names and every `cidrs_by_az` key must be changed together when selecting another Region or AZ set.
- Review the data-tier and endpoint-tier CIDRs, tags, and Lattice authorization model against organizational controls before deployment.
- **Cost:** three public NAT Gateways, three public IPv4 addresses, CloudWatch Logs ingestion and retention, traffic processing, regional transfer, and VPC Lattice usage can incur charges.

## Run

```shell
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output subnet_cidrs
terraform output lattice_association_id
terraform destroy
```

The isolated subnet roles create no default internet or transit routes; application access to the data and endpoint tiers must be authorized separately with security groups, endpoint policies, and service policies.
