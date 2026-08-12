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
      toset(keys(output.route_tables)) == toset(["app", "database", "public"])
    )
    error_message = "The basic example must plan Flow Logs and route-table outputs."
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
