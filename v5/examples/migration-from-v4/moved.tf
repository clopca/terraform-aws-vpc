# v4 -> v5 state moves for the representative two-AZ example.
#
# Copy this file to moved.tf in the caller root, then replace AZs, private
# groups, and route destinations with the exact current state/configuration.
# Remove any block whose source is absent. Keep the file until every workspace
# has applied the upgrade. Terraform moved blocks do not support wildcards.
#
# 63 active moved blocks. aws_vpc.main[0] and aws_internet_gateway.main[0]
# retain their addresses. The v4 CloudWatch log group deliberately has no
# moved block: preserve its generated physical name, remove only its old state
# address, and import it at aws_cloudwatch_log_group.flow_logs["default"]. See
# docs/rfc/v5-migration.md for that cutover, secondary CIDR, S3, IAM policy-type
# changes, injected resources, and other non-movable cases.

moved {
  from = module.vpc.aws_subnet.public["us-east-1a"]
  to   = module.vpc.aws_subnet.main["public/us-east-1a"]
}

moved {
  from = module.vpc.aws_route_table.public["us-east-1a"]
  to   = module.vpc.aws_route_table.main["public/us-east-1a"]
}

moved {
  from = module.vpc.aws_route_table_association.public["us-east-1a"]
  to   = module.vpc.aws_route_table_association.main["public/us-east-1a"]
}

moved {
  from = module.vpc.aws_subnet.public["us-east-1b"]
  to   = module.vpc.aws_subnet.main["public/us-east-1b"]
}

moved {
  from = module.vpc.aws_route_table.public["us-east-1b"]
  to   = module.vpc.aws_route_table.main["public/us-east-1b"]
}

moved {
  from = module.vpc.aws_route_table_association.public["us-east-1b"]
  to   = module.vpc.aws_route_table_association.main["public/us-east-1b"]
}

moved {
  from = module.vpc.aws_subnet.private["app/us-east-1a"]
  to   = module.vpc.aws_subnet.main["app/us-east-1a"]
}

moved {
  from = module.vpc.aws_route_table.private["app/us-east-1a"]
  to   = module.vpc.aws_route_table.main["app/us-east-1a"]
}

moved {
  from = module.vpc.aws_route_table_association.private["app/us-east-1a"]
  to   = module.vpc.aws_route_table_association.main["app/us-east-1a"]
}

moved {
  from = module.vpc.aws_subnet.private["app/us-east-1b"]
  to   = module.vpc.aws_subnet.main["app/us-east-1b"]
}

moved {
  from = module.vpc.aws_route_table.private["app/us-east-1b"]
  to   = module.vpc.aws_route_table.main["app/us-east-1b"]
}

moved {
  from = module.vpc.aws_route_table_association.private["app/us-east-1b"]
  to   = module.vpc.aws_route_table_association.main["app/us-east-1b"]
}

moved {
  from = module.vpc.aws_subnet.tgw["us-east-1a"]
  to   = module.vpc.aws_subnet.main["transit_gateway/us-east-1a"]
}

moved {
  from = module.vpc.aws_route_table.tgw["us-east-1a"]
  to   = module.vpc.aws_route_table.main["transit_gateway/us-east-1a"]
}

moved {
  from = module.vpc.aws_route_table_association.tgw["us-east-1a"]
  to   = module.vpc.aws_route_table_association.main["transit_gateway/us-east-1a"]
}

moved {
  from = module.vpc.aws_subnet.tgw["us-east-1b"]
  to   = module.vpc.aws_subnet.main["transit_gateway/us-east-1b"]
}

moved {
  from = module.vpc.aws_route_table.tgw["us-east-1b"]
  to   = module.vpc.aws_route_table.main["transit_gateway/us-east-1b"]
}

moved {
  from = module.vpc.aws_route_table_association.tgw["us-east-1b"]
  to   = module.vpc.aws_route_table_association.main["transit_gateway/us-east-1b"]
}

moved {
  from = module.vpc.aws_subnet.cwan["us-east-1a"]
  to   = module.vpc.aws_subnet.main["core_network/us-east-1a"]
}

moved {
  from = module.vpc.aws_route_table.cwan["us-east-1a"]
  to   = module.vpc.aws_route_table.main["core_network/us-east-1a"]
}

moved {
  from = module.vpc.aws_route_table_association.cwan["us-east-1a"]
  to   = module.vpc.aws_route_table_association.main["core_network/us-east-1a"]
}

moved {
  from = module.vpc.aws_subnet.cwan["us-east-1b"]
  to   = module.vpc.aws_subnet.main["core_network/us-east-1b"]
}

moved {
  from = module.vpc.aws_route_table.cwan["us-east-1b"]
  to   = module.vpc.aws_route_table.main["core_network/us-east-1b"]
}

moved {
  from = module.vpc.aws_route_table_association.cwan["us-east-1b"]
  to   = module.vpc.aws_route_table_association.main["core_network/us-east-1b"]
}

moved {
  from = module.vpc.aws_eip.nat["us-east-1a"]
  to   = module.vpc.aws_eip.nat["nat/us-east-1a"]
}

moved {
  from = module.vpc.aws_nat_gateway.main["us-east-1a"]
  to   = module.vpc.aws_nat_gateway.main["nat/us-east-1a"]
}

moved {
  from = module.vpc.aws_eip.nat["us-east-1b"]
  to   = module.vpc.aws_eip.nat["nat/us-east-1b"]
}

moved {
  from = module.vpc.aws_nat_gateway.main["us-east-1b"]
  to   = module.vpc.aws_nat_gateway.main["nat/us-east-1b"]
}

moved {
  from = module.vpc.aws_egress_only_internet_gateway.eigw[0]
  to   = module.vpc.aws_egress_only_internet_gateway.main[0]
}

moved {
  from = module.vpc.aws_route.public_to_igw["us-east-1a"]
  to   = module.vpc.aws_route.igw_ipv4["public/us-east-1a/igw"]
}

moved {
  from = module.vpc.aws_route.public_ipv6_to_igw["us-east-1a"]
  to   = module.vpc.aws_route.igw_ipv6["public/us-east-1a/igw6"]
}

moved {
  from = module.vpc.aws_route.private_to_nat["app/us-east-1a"]
  to   = module.vpc.aws_route.nat["app/us-east-1a/nat"]
}

moved {
  from = module.vpc.aws_route.private_to_egress_only["app/us-east-1a"]
  to   = module.vpc.aws_route.eigw["app/us-east-1a/eigw"]
}

moved {
  from = module.vpc.aws_route.tgw_to_nat["us-east-1a"]
  to   = module.vpc.aws_route.nat["transit_gateway/us-east-1a/nat"]
}

moved {
  from = module.vpc.aws_route.cwan_to_nat["us-east-1a"]
  to   = module.vpc.aws_route.nat["core_network/us-east-1a/nat"]
}

moved {
  from = module.vpc.aws_route.public_to_igw["us-east-1b"]
  to   = module.vpc.aws_route.igw_ipv4["public/us-east-1b/igw"]
}

moved {
  from = module.vpc.aws_route.public_ipv6_to_igw["us-east-1b"]
  to   = module.vpc.aws_route.igw_ipv6["public/us-east-1b/igw6"]
}

moved {
  from = module.vpc.aws_route.private_to_nat["app/us-east-1b"]
  to   = module.vpc.aws_route.nat["app/us-east-1b/nat"]
}

moved {
  from = module.vpc.aws_route.private_to_egress_only["app/us-east-1b"]
  to   = module.vpc.aws_route.eigw["app/us-east-1b/eigw"]
}

moved {
  from = module.vpc.aws_route.tgw_to_nat["us-east-1b"]
  to   = module.vpc.aws_route.nat["transit_gateway/us-east-1b/nat"]
}

moved {
  from = module.vpc.aws_route.cwan_to_nat["us-east-1b"]
  to   = module.vpc.aws_route.nat["core_network/us-east-1b/nat"]
}

moved {
  from = module.vpc.aws_route.public_to_tgw["us-east-1a"]
  to   = module.vpc.aws_route.tgw["public/us-east-1a/tgw/10.0.0.0-8"]
}

moved {
  from = module.vpc.aws_route.ipv6_public_to_tgw["us-east-1a"]
  to   = module.vpc.aws_route.tgw_ipv6["public/us-east-1a/tgw6/2001:db8:100::-48"]
}

moved {
  from = module.vpc.aws_route.public_to_tgw["us-east-1b"]
  to   = module.vpc.aws_route.tgw["public/us-east-1b/tgw/10.0.0.0-8"]
}

moved {
  from = module.vpc.aws_route.ipv6_public_to_tgw["us-east-1b"]
  to   = module.vpc.aws_route.tgw_ipv6["public/us-east-1b/tgw6/2001:db8:100::-48"]
}

moved {
  from = module.vpc.aws_route.private_to_tgw["app/us-east-1a"]
  to   = module.vpc.aws_route.tgw["app/us-east-1a/tgw/172.16.0.0-12"]
}

moved {
  from = module.vpc.aws_route.ipv6_private_to_tgw["app/us-east-1a"]
  to   = module.vpc.aws_route.tgw_ipv6["app/us-east-1a/tgw6/2001:db8:200::-48"]
}

moved {
  from = module.vpc.aws_route.private_to_tgw["app/us-east-1b"]
  to   = module.vpc.aws_route.tgw["app/us-east-1b/tgw/172.16.0.0-12"]
}

moved {
  from = module.vpc.aws_route.ipv6_private_to_tgw["app/us-east-1b"]
  to   = module.vpc.aws_route.tgw_ipv6["app/us-east-1b/tgw6/2001:db8:200::-48"]
}

moved {
  from = module.vpc.aws_route.public_to_cwan["us-east-1a"]
  to   = module.vpc.aws_route.cwan["public/us-east-1a/cwan/100.64.0.0-10"]
}

moved {
  from = module.vpc.aws_route.ipv6_public_to_cwan["us-east-1a"]
  to   = module.vpc.aws_route.cwan_ipv6["public/us-east-1a/cwan6/2001:db8:300::-48"]
}

moved {
  from = module.vpc.aws_route.public_to_cwan["us-east-1b"]
  to   = module.vpc.aws_route.cwan["public/us-east-1b/cwan/100.64.0.0-10"]
}

moved {
  from = module.vpc.aws_route.ipv6_public_to_cwan["us-east-1b"]
  to   = module.vpc.aws_route.cwan_ipv6["public/us-east-1b/cwan6/2001:db8:300::-48"]
}

moved {
  from = module.vpc.aws_route.private_to_cwan["app/us-east-1a"]
  to   = module.vpc.aws_route.cwan["app/us-east-1a/cwan/192.168.0.0-16"]
}

moved {
  from = module.vpc.aws_route.ipv6_private_to_cwan["app/us-east-1a"]
  to   = module.vpc.aws_route.cwan_ipv6["app/us-east-1a/cwan6/2001:db8:400::-48"]
}

moved {
  from = module.vpc.aws_route.private_to_cwan["app/us-east-1b"]
  to   = module.vpc.aws_route.cwan["app/us-east-1b/cwan/192.168.0.0-16"]
}

moved {
  from = module.vpc.aws_route.ipv6_private_to_cwan["app/us-east-1b"]
  to   = module.vpc.aws_route.cwan_ipv6["app/us-east-1b/cwan6/2001:db8:400::-48"]
}

moved {
  from = module.vpc.aws_ec2_transit_gateway_vpc_attachment.tgw[0]
  to   = module.vpc.aws_ec2_transit_gateway_vpc_attachment.this["vpc"]
}

moved {
  from = module.vpc.aws_networkmanager_vpc_attachment.cwan[0]
  to   = module.vpc.aws_networkmanager_vpc_attachment.this["vpc"]
}

moved {
  from = module.vpc.aws_networkmanager_attachment_accepter.cwan[0]
  to   = module.vpc.aws_networkmanager_attachment_accepter.this["vpc"]
}

moved {
  from = module.vpc.aws_vpclattice_service_network_vpc_association.vpc_lattice_service_network_association[0]
  to   = module.vpc.aws_vpclattice_service_network_vpc_association.this["vpc"]
}

moved {
  from = module.vpc.module.flow_logs[0].aws_flow_log.main
  to   = module.vpc.aws_flow_log.this["default"]
}

moved {
  from = module.vpc.module.flow_logs[0].module.cloudwatch_log_group[0].aws_iam_role.main
  to   = module.vpc.aws_iam_role.flow_logs["default"]
}
