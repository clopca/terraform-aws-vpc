# Secure isolated enclave

This example combines the v5 D6 controls into an enclave/air-gapped topology:

- VPC Block Public Access in `block-bidirectional` mode;
- a custom DHCP option set with a private domain, Amazon-provided DNS, and Amazon Time Sync;
- opt-in adoption of the AWS-created default security group, network ACL, and route table;
- two subnet groups whose semantic role is exclusively `isolated`;
- no Internet Gateway, egress-only Internet Gateway, NAT Gateway, or managed egress route.

Use this pattern for restricted processing zones, offline control planes, regulated data enclaves, or workloads whose ingress and egress must traverse separately governed private endpoints or inspection infrastructure. Add VPC endpoints and explicit private connectivity as separate resources; do not change an isolated group into a routed group implicitly.

```mermaid
flowchart TB
  BPA[VPC Block Public Access\nblock bidirectional] --> VPC[Secure VPC]
  DHCP[Custom DHCP options] --> VPC
  VPC --> Enclave[Enclave subnets\n2 AZs]
  VPC --> Control[Control subnets\n2 AZs]
  Internet((Internet)) -. blocked / no route .-> VPC
```

## Default-resource adoption warning

`default_resources` does not create replacements. It adopts AWS-created defaults.
On first apply, security-group rules, default NACL allow rules, non-local default
routes, and propagated gateways are removed. Enabling it in a live VPC can break
workloads still using those defaults; inventory dependencies and move workloads to
explicit SGs, NACLs, and route tables first. All selectors default to `false`, so
existing deployments and v4 migration plans remain unchanged unless explicitly
enabled.

## Regional singleton warning

`aws_vpc_block_public_access_options` is an account/Region singleton. Manage it from exactly one module instance. Applying this example changes the regional setting and can affect other VPCs in the account, so use an isolated test account or coordinate the change with the account networking owner.

## Run

```shell
terraform init
terraform plan
terraform apply
terraform output egress_resources
terraform destroy
```

A clean plan should show no IGW, NAT Gateway, EIGW, or egress routes. Destroy removes the regional BPA configuration created by this example, so do not use it as an uncoordinated demonstration in a shared account.
