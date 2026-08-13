mock_provider "aws" {
  override_during = plan

  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }

  mock_resource "aws_vpc" {
    defaults = {
      id         = "vpc-mock"
      arn        = "arn:aws:ec2:us-east-1:123456789012:vpc/vpc-mock"
      cidr_block = "10.96.0.0/16"
    }
  }

  mock_resource "aws_subnet" {
    defaults = { id = "subnet-mock" }
  }

  mock_resource "aws_vpc_endpoint" {
    defaults = { id = "vpce-s3" }
  }
}

run "shared_physical_route_table_is_materialized_once" {
  command = plan

  variables {
    vpc                = { name = "shared-route-table" }
    addressing         = { ipv4 = { cidr_block = "10.96.0.0/16" } }
    availability_zones = { names = ["us-east-1a", "us-east-1b"] }
    subnets = {
      public_a = {
        role               = "public"
        ipv4               = { cidrs_by_az = { us-east-1a = "10.96.0.0/24", us-east-1b = "10.96.1.0/24" } }
        manage_route_table = false
        route_table_key    = "shared-public"
        route_table_id     = "rtb-shared"
        routing            = { s3_gateway_endpoint = true }
      }
      public_b = {
        role               = "public"
        ipv4               = { cidrs_by_az = { us-east-1a = "10.96.2.0/24", us-east-1b = "10.96.3.0/24" } }
        manage_route_table = false
        route_table_key    = "shared-public"
        route_table_id     = "rtb-shared"
        routing            = { s3_gateway_endpoint = true }
      }
    }
    gateway_endpoints = { s3 = { service = "s3" } }
  }

  assert {
    condition = (
      length(aws_route_table_association.main) == 4 &&
      toset(keys(aws_route.igw_ipv4)) == toset(["injected/shared-public/igw"]) &&
      toset(keys(aws_vpc_endpoint_route_table_association.gateway)) == toset(["injected/shared-public/gateway-endpoint/s3"])
    )
    error_message = "Two groups sharing one physical route_table_key must retain four subnet associations but create each physical route/endpoint association once."
  }
}

run "reject_route_table_key_with_different_ids" {
  command = plan

  variables {
    vpc                = { name = "invalid-route-table-identity" }
    addressing         = { ipv4 = { cidr_block = "10.97.0.0/16" } }
    availability_zones = { names = ["us-east-1a"] }
    subnets = {
      app = {
        role               = "private"
        ipv4               = { cidrs_by_az = { us-east-1a = "10.97.0.0/24" } }
        manage_route_table = false
        route_table_key    = "shared"
        route_table_id     = "rtb-one"
      }
      data = {
        role               = "private"
        ipv4               = { cidrs_by_az = { us-east-1a = "10.97.1.0/24" } }
        manage_route_table = false
        route_table_key    = "shared"
        route_table_id     = "rtb-two"
      }
    }
  }

  expect_failures = [terraform_data.injected_route_table_identity_validation[0]]
}
