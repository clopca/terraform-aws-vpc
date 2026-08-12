mock_provider "aws" {
  override_during = plan

  mock_data "aws_vpc" {
    defaults = {
      id         = "vpc-upstream"
      arn        = "arn:aws:ec2:us-east-1:123456789012:vpc/vpc-upstream"
      cidr_block = "10.0.0.0/16"
    }
  }

  mock_resource "aws_subnet" {
    defaults = {
      id  = "subnet-mock"
      arn = "arn:aws:ec2:us-east-1:123456789012:subnet/subnet-mock"
    }
  }

  mock_resource "aws_flow_log" {
    defaults = { id = "fl-mock" }
  }

  mock_resource "aws_vpclattice_service_network_vpc_association" {
    defaults = { id = "snva-mock" }
  }
}

run "computed_ids_keep_collection_keys_plan_known" {
  command = plan

  module {
    source = "./tests/fixtures/computed-inputs"
  }

  assert {
    condition = (
      output.composition_shape.subnet_groups == ["ipam", "public"] &&
      output.composition_shape.route_table_groups == ["ipam", "public"] &&
      output.composition_shape.flow_log_keys == ["audit"] &&
      output.composition_shape.created_vpcs == 0 &&
      output.composition_shape.created_igws == 0 &&
      output.composition_shape.created_route_tables == 1 &&
      output.composition_shape.lattice_associations == 1
    )
    error_message = "Computed IDs must remain values; all resource keys and ownership decisions must come from explicit configuration."
  }
}
