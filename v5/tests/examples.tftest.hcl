mock_provider "aws" {
  override_during = plan

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }

  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }

  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }

  mock_resource "aws_vpc" {
    defaults = {
      id              = "vpc-mock"
      arn             = "arn:aws:ec2:us-east-1:123456789012:vpc/vpc-mock"
      cidr_block      = "10.0.0.0/16"
      ipv6_cidr_block = "2600:1f18:4200::/56"
    }
  }

  mock_data "aws_vpc" {
    defaults = {
      id         = "vpc-mock"
      arn        = "arn:aws:ec2:us-east-1:123456789012:vpc/vpc-mock"
      cidr_block = "10.80.0.0/16"
    }
  }

  mock_data "aws_network_acls" {
    defaults = { ids = ["acl-default"] }
  }

  mock_data "aws_route_table" {
    defaults = { id = "rtb-default" }
  }

  mock_resource "aws_subnet" {
    defaults = {
      id              = "subnet-mock"
      arn             = "arn:aws:ec2:us-east-1:123456789012:subnet/subnet-mock"
      ipv6_cidr_block = ""
    }
  }

  mock_resource "aws_vpclattice_service_network" {
    defaults = { id = "sn-mock" }
  }
}

run "basic_example" {
  command = plan

  module {
    source = "./examples/basic"
  }

  assert {
    condition = (
      toset(keys(output.subnet_ids)) == toset(["app", "database", "public"]) &&
      length(output.subnet_ids.public) == 3 &&
      alltrue([for cidr in values(output.subnet_ipv6_cidrs.public) : cidr != null && cidr != ""]) &&
      alltrue([for cidr in values(output.subnet_ipv6_cidrs.app) : cidr != null && cidr != ""]) &&
      alltrue([for cidr in values(output.subnet_ipv6_cidrs.database) : cidr == null])
    )
    error_message = "The basic example must select exactly three AZs and plan real dual-stack subnets."
  }

  assert {
    condition = (
      length(output.flow_log_ids) == 1 &&
      toset(keys(output.route_tables)) == toset(["app", "database", "public"]) &&
      toset(keys(output.gateway_endpoints.ids)) == toset(["dynamodb", "s3"]) &&
      output.gateway_endpoints.association_count == 6
    )
    error_message = "The basic example must plan Flow Logs, route tables, and both gateway endpoints across all application AZs."
  }
}

run "enterprise_example" {
  command = plan

  module {
    source = "./examples/enterprise"
  }

  assert {
    condition = (
      toset(keys(output.subnet_ids)) == toset(["application", "data", "endpoints", "public"])
    )
    error_message = "The enterprise example must plan all four documented subnet groups."
  }

  assert {
    condition = (
      length(output.nat_gateway_ids) == 3 && length(output.flow_log_ids) == 1 &&
      alltrue([for cidr in values(output.subnet_ipv6_cidrs.public) : cidr != null && cidr != ""]) &&
      alltrue([for cidr in values(output.subnet_ipv6_cidrs.application) : cidr != null && cidr != ""])
    )
    error_message = "The enterprise example must plan three NAT Gateways, one S3 Flow Log, and real dual-stack subnets."
  }
}

run "hub_example" {
  command = plan

  module {
    source = "./examples/hub"
  }

  variables {
    existing_igw_id          = "igw-0123456789abcdef0"
    transit_gateway_id       = "tgw-0123456789abcdef0"
    core_network_id          = "cnet-0123456789abcdef0"
    core_network_arn         = "arn:aws:networkmanager::123456789012:core-network/cnet-0123456789abcdef0"
    flow_log_destination_arn = "arn:aws:firehose:us-west-2:123456789012:deliverystream/network-hub-vpc-flow-logs"
    nat_eip_allocation_ids = {
      us-west-2a = "eipalloc-01111111111111111"
      us-west-2b = "eipalloc-02222222222222222"
      us-west-2c = "eipalloc-03333333333333333"
    }
  }

  assert {
    condition = (
      toset(keys(output.subnet_ids)) == toset(["cwan", "edge", "firewall", "public", "tgw"])
    )
    error_message = "The hub example must plan all five documented subnet groups."
  }

  assert {
    condition = (
      length(output.flow_log_ids) == 1 && length(output.inspection_nat_ids) == 2 &&
      toset(keys(output.route_tables)) == toset(["cwan", "edge", "firewall", "public", "tgw"]) &&
      alltrue(flatten([for group in ["public", "edge", "firewall", "tgw", "cwan"] : [
        for cidr in values(output.subnet_ipv6_cidrs[group]) : cidr != null && cidr != ""
      ]]))
    )
    error_message = "The hub example must plan non-overlapping dual-stack subnets, Firehose Flow Logs, route tables, and two inspection NAT Gateways."
  }
}

run "nat_byoip_example" {
  command = plan

  module {
    source = "./examples/nat_byoip"
  }

  assert {
    condition = (
      toset(keys(output.nat_gateway_ids)) == toset(["byoip_pool", "create", "existing", "regional"]) &&
      alltrue([for ids in values(output.nat_gateway_ids) : length(ids) == 2]) &&
      alltrue([for mode in ["byoip_pool", "create", "existing"] : length(output.nat_eip_allocation_ids[mode]) == 2])
    )
    error_message = "The NAT BYOIP example must plan three two-AZ zonal modes plus one Regional NAT whose ID is repeated across AZ output keys."
  }
}

run "ipam_example" {
  command = plan

  module {
    source = "./examples/ipam"
  }

  assert {
    condition = (
      toset(keys(output.secondary_cidr_association_ids)) == toset(["analytics", "legacy"]) &&
      toset(keys(output.subnet_ids)) == toset(["analytics", "application", "legacy"]) &&
      alltrue([for subnets in values(output.subnet_ids) : length(subnets) == 2])
    )
    error_message = "The IPAM example must plan primary/IPAM and named secondary addressing across all documented subnet groups."
  }
}

run "dual_stack_example" {
  command = plan

  module {
    source = "./examples/dual_stack"
  }

  assert {
    condition = (
      alltrue(flatten([for group in ["public", "application", "ipv6-native"] : [
        for cidr in values(output.subnet_ipv6_cidrs[group]) : cidr != null && cidr != ""
      ]])) &&
      length(output.ipv6_native_subnet_ids) == 2 &&
      output.ipv6_route_counts.internet_gateway == 2 &&
      output.ipv6_route_counts.egress_only_igw == 4 &&
      output.ipv6_route_counts.nat64 == 2
    )
    error_message = "The dual-stack example must plan dual-stack and IPv6-native subnets plus IGW, EIGW, and NAT64 routes."
  }
}

run "existing_vpc_example" {
  command = plan

  module {
    source = "./examples/existing_vpc"
  }

  assert {
    condition = (
      toset(keys(output.subnet_ids)) == toset(["application", "public"]) &&
      length(output.nat_gateway_ids) == 2 &&
      output.module_ownership.vpcs == 0 &&
      output.module_ownership.internet_gateways == 0 &&
      output.module_ownership.elastic_ips == 0 &&
      toset(keys(output.module_ownership.injected_route_tables)) == toset(["external-public"])
    )
    error_message = "The existing-VPC example must inject its VPC, IGW, public route table, and NAT EIPs while creating subnets and two NAT Gateways."
  }
}

run "secure_isolated_example" {
  command = plan

  module {
    source = "./examples/secure_isolated"
  }

  assert {
    condition = (
      toset(keys(output.isolated_subnet_ids)) == toset(["control", "enclave"]) &&
      output.egress_resources.internet_gateway_id == null &&
      length(output.egress_resources.nat_gateway_ids) == 0 &&
      output.egress_resources.egress_only_igw_id == null &&
      output.route_counts.internet == 0 &&
      output.route_counts.nat == 0 &&
      output.route_counts.eigw == 0 &&
      output.default_resource_hardening.security_group_count == 1 &&
      output.default_resource_hardening.network_acl_count == 1 &&
      output.default_resource_hardening.route_table_count == 1 &&
      toset(keys(output.network_acl_controls.ids)) == toset(["control", "enclave"]) &&
      output.network_acl_controls.rule_count == 4 &&
      output.network_acl_controls.association_count == 4
    )
    error_message = "The secure isolated example must harden defaults, manage two explicit stateless NACLs, and retain no egress resources."
  }
}

run "private_nat_example" {
  command = plan

  module {
    source = "./examples/private_nat"
  }

  variables {
    transit_gateway_id = "tgw-0123456789abcdef0"
  }

  assert {
    condition = (
      toset(keys(output.subnet_ids)) == toset(["nat-host", "tgw", "workload"]) &&
      length(output.private_nat_gateway_ids) == 2 &&
      length(output.nat_public_ips) == 0 &&
      output.route_counts.workload_to_nat == 2 &&
      output.route_counts.nat_to_tgw == 4 &&
      output.route_counts.internet == 0
    )
    error_message = "The private-NAT example must plan two private NAT Gateways, workload NAT routes, four translated TGW routes, and no Internet route."
  }
}

run "inspection_egress_example" {
  command = plan

  module {
    source = "./examples/inspection_egress"
  }

  variables {
    transit_gateway_id   = "tgw-0123456789abcdef0"
    spoke_prefix_list_id = "pl-0123456789abcdef0"
  }

  assert {
    condition = (
      toset(keys(output.subnet_ids)) == toset(["firewall", "public", "tgw_attach"]) &&
      length(output.nat_gateway_ids) == 3 &&
      output.network_firewall_inputs.number_azs == 3 &&
      toset(keys(output.network_firewall_inputs.vpc_subnets)) == toset(["us-east-1a", "us-east-1b", "us-east-1c"]) &&
      toset(keys(output.network_firewall_inputs.routing_configuration.centralized_inspection_with_egress.connectivity_subnet_route_tables)) == toset(["us-east-1a", "us-east-1b", "us-east-1c"]) &&
      output.route_evidence.internet_routes == 3 &&
      output.route_evidence.nat_routes == 3 &&
      output.route_evidence.tgw_routes == 3 &&
      alltrue([for destination in values(output.route_evidence.tgw_destinations) :
        destination.cidr_block == null && destination.prefix_list_id == "pl-0123456789abcdef0"
      ])
    )
    error_message = "The inspection-egress example must plan three-AZ NAT egress, appliance-path TGW prefix-list routes, and complete Tier 1 Network Firewall inputs."
  }
}
