mock_provider "aws" {
  override_during = plan

  mock_resource "aws_vpc" {
    defaults = {
      id         = "vpc-mock"
      arn        = "arn:aws:ec2:us-east-1:123456789012:vpc/vpc-mock"
      cidr_block = "10.60.0.0/16"
    }
  }

  mock_data "aws_network_acls" {
    defaults = { ids = ["acl-default"] }
  }

  mock_data "aws_route_table" {
    defaults = { id = "rtb-default" }
  }

  mock_resource "aws_default_security_group" {
    defaults = { id = "sg-default" }
  }

  mock_resource "aws_default_network_acl" {
    defaults = { id = "acl-default" }
  }

  mock_resource "aws_default_route_table" {
    defaults = { id = "rtb-default" }
  }
}

run "adopt_and_harden_default_resources" {
  command = plan

  variables {
    vpc                = { name = "secure-defaults" }
    addressing         = { ipv4 = { cidr_block = "10.60.0.0/16" } }
    availability_zones = { names = ["us-east-1a"] }
    subnets            = {}
    default_resources = {
      manage_security_group = true
      manage_network_acl    = true
      manage_route_table    = true
      name_format           = "legacy-{vpc}-{resource}"
      tags                  = { Control = "CIS-4.3" }
    }
  }

  assert {
    condition = (
      length(aws_default_security_group.this) == 1 &&
      length(aws_default_security_group.this["default"].ingress) == 0 &&
      length(aws_default_security_group.this["default"].egress) == 0 &&
      aws_default_security_group.this["default"].tags.Name == "legacy-secure-defaults-default-security-group" &&
      aws_default_network_acl.this["default"].tags.Name == "legacy-secure-defaults-default-network-acl" &&
      aws_default_route_table.this["default"].tags.Name == "legacy-secure-defaults-default-route-table" &&
      length(aws_default_route_table.this["default"].route) == 0 &&
      length(aws_default_route_table.this["default"].propagating_vgws) == 0
    )
    error_message = "Default-resource opt-in must adopt all three defaults, remove SG rules/non-local routes, and apply deterministic Names."
  }

  assert {
    condition = output.default_resource_ids == {
      security_group = "sg-default"
      network_acl    = "acl-default"
      route_table    = "rtb-default"
    }
    error_message = "Tier 1 must expose the adopted default-resource IDs."
  }
}

run "reject_invalid_default_resource_name_format" {
  command = plan

  variables {
    vpc                = { name = "invalid-defaults" }
    addressing         = { ipv4 = { cidr_block = "10.61.0.0/16" } }
    availability_zones = { names = ["us-east-1a"] }
    subnets            = {}
    default_resources  = { name_format = "{vpc}-{unknown}" }
  }

  expect_failures = [var.default_resources]
}
