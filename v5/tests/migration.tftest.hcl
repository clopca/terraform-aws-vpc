mock_provider "aws" {
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
      default_security_group_id = "sg-default"
      default_network_acl_id    = "acl-default"
      default_route_table_id    = "rtb-default"
      main_route_table_id       = "rtb-default"
    }
  }
}

run "seed_representative_v4_state" {
  command   = apply
  state_key = "representative-moved-state"

  module {
    source = "./tests/fixtures/moved-v4"
  }

  assert {
    condition = (
      output.subnet_id != null && output.route_table_id != null && output.association_id != null &&
      output.vpc_assign_generated_ipv6_cidr_block
    )
    error_message = "The mocked v4 fixture must seed subnet, route-table, association, and embedded IPv6 VPC state."
  }
}

run "plan_representative_v5_moves" {
  command   = plan
  state_key = "representative-moved-state"

  module {
    source = "./tests/fixtures/moved-v5"
  }

  assert {
    condition     = output.subnet_keys == ["public/us-east-1a"]
    error_message = "The moved subnet must use the unified v5 group/AZ key."
  }

  assert {
    condition     = output.subnet_id == run.seed_representative_v4_state.subnet_id
    error_message = "The subnet ID must remain known and unchanged after the state move."
  }

  assert {
    condition = (
      output.route_table_id == run.seed_representative_v4_state.route_table_id &&
      output.association_id == run.seed_representative_v4_state.association_id
    )
    error_message = "Route-table and association IDs must remain known and unchanged after state moves."
  }

  assert {
    condition = (
      output.vpc_assign_generated_ipv6_cidr_block ==
      run.seed_representative_v4_state.vpc_assign_generated_ipv6_cidr_block
    )
    error_message = "The v5 VPC lifecycle bridge must preserve embedded IPv6 state; true-to-null would make the provider disassociate the live prefix."
  }
}

run "validate_root_migration_handoff_syntax" {
  command = plan

  module {
    source = "./tests/fixtures/migration-root-handoff"
  }
}

run "plan_full_migration_example" {
  command   = plan
  state_key = "full-migration-syntax"

  module {
    source = "./examples/migration-from-v4"
  }

  assert {
    condition     = keys(output.v4_private_subnet_attributes_by_az) == ["app/us-east-1a", "app/us-east-1b"]
    error_message = "The complete migration example, including all 63 moved blocks, must plan with v4-compatible private keys."
  }

  assert {
    condition = (
      output.default_resource_management.security_group_count == 0 &&
      output.default_resource_management.network_acl_count == 0 &&
      output.default_resource_management.route_table_count == 0
    )
    error_message = "Default ID observation must not adopt lifecycle ownership during migration."
  }

  assert {
    condition = output.v4_name_compatibility == {
      public_subnet      = "public-us-east-1a"
      app_route_table    = "app-us-east-1a"
      nat_eip            = "nat-public-us-east-1a"
      nat_gateway        = "nat-public-us-east-1a"
      internet_gateway   = "migration-example-igw"
      egress_only_igw    = "migration-example"
      flow_log           = "migration-example"
      log_group_has_name = false
    }
    error_message = "The migration example must reproduce all v4 Name tags exactly, including the Flow Log Name and absent log-group Name."
  }
}
