mock_provider "aws" {
  override_during = plan

  mock_resource "aws_vpc" {
    defaults = {
      id         = "vpc-mock"
      arn        = "arn:aws:ec2:us-east-1:123456789012:vpc/vpc-mock"
      cidr_block = "10.130.0.0/16"
    }
  }

  mock_resource "aws_subnet" {
    defaults = { id = "subnet-mock" }
  }

  mock_resource "aws_route_table" {
    defaults = { id = "rtb-mock" }
  }
}

run "top_level_static_target_expands_by_az" {
  command = plan

  variables {
    vpc                = { name = "top-level-static" }
    addressing         = { primary = { cidr_block = "10.130.0.0/16" } }
    availability_zones = { names = ["us-east-1a", "us-east-1b"] }
    subnets = {
      app = {
        role = "private"
        ipv4 = { cidrs_by_az = { us-east-1a = "10.130.0.0/24", us-east-1b = "10.130.1.0/24" } }
      }
    }
    routes = {
      services = {
        from_group  = "app"
        destination = { type = "ipv4_cidr", value = "10.200.0.0/16" }
        target      = { type = "vpc_peering", id = "pcx-documentation" }
      }
    }
  }

  assert {
    condition = (
      toset(keys(aws_route.top_level)) == toset(["services/us-east-1a", "services/us-east-1b"]) &&
      alltrue([for route in values(aws_route.top_level) : route.vpc_peering_connection_id == "pcx-documentation"])
    )
    error_message = "A static top-level target must expand with stable <route-key>/<az> addresses and one target value."
  }
}

run "top_level_zonal_targets_cover_all_destination_types" {
  command = plan

  variables {
    vpc                = { name = "top-level-zonal" }
    addressing         = { primary = { cidr_block = "10.131.0.0/16" } }
    availability_zones = { names = ["us-east-1a", "us-east-1b"] }
    subnets = {
      app = {
        role = "private"
        ipv4 = { cidrs_by_az = { us-east-1a = "10.131.0.0/24", us-east-1b = "10.131.1.0/24" } }
      }
    }
    routes = {
      inspect-v4 = {
        from_group  = "app"
        destination = { type = "ipv4_cidr", value = "0.0.0.0/0" }
        target = {
          type      = "vpc_endpoint"
          ids_by_az = { us-east-1a = "vpce-a", us-east-1b = "vpce-b" }
        }
      }
      inspect-v6 = {
        from_group  = "app"
        destination = { type = "ipv6_cidr", value = "::/0" }
        target = {
          type      = "vpc_endpoint"
          ids_by_az = { us-east-1a = "vpce-a", us-east-1b = "vpce-b" }
        }
      }
      managed-service = {
        from_group  = "app"
        destination = { type = "prefix_list", value = "pl-0123456789abcdef0" }
        target = {
          type      = "network_interface"
          ids_by_az = { us-east-1a = "eni-a", us-east-1b = "eni-b" }
        }
      }
    }
  }

  assert {
    condition = (
      length(aws_route.top_level) == 6 &&
      aws_route.top_level["inspect-v4/us-east-1a"].destination_cidr_block == "0.0.0.0/0" &&
      aws_route.top_level["inspect-v6/us-east-1b"].destination_ipv6_cidr_block == "::/0" &&
      aws_route.top_level["managed-service/us-east-1a"].destination_prefix_list_id == "pl-0123456789abcdef0" &&
      aws_route.top_level["inspect-v4/us-east-1a"].vpc_endpoint_id == "vpce-a" &&
      aws_route.top_level["inspect-v4/us-east-1b"].vpc_endpoint_id == "vpce-b" &&
      aws_route.top_level["managed-service/us-east-1b"].network_interface_id == "eni-b"
    )
    error_message = "Zonal targets must select the matching AZ ID for IPv4, IPv6, and prefix-list destinations."
  }
}

run "computed_zonal_targets_do_not_create_a_module_cycle" {
  command = plan

  module {
    source = "./tests/fixtures/zonal-route-composition"
  }

  assert {
    condition = (
      output.composition_shape.endpoint_keys == ["us-east-1a", "us-east-1b"] &&
      output.composition_shape.subnet_keys == ["us-east-1a", "us-east-1b"] &&
      output.composition_shape.route_table_keys == ["us-east-1a", "us-east-1b"]
    )
    error_message = "A target resource consuming VPC subnet outputs must feed computed zonal IDs back into top-level routes without a dependency cycle."
  }
}

run "reject_top_level_target_with_both_id_forms" {
  command = plan

  variables {
    vpc                = { name = "xor-both" }
    addressing         = { primary = { cidr_block = "10.132.0.0/16" } }
    availability_zones = { names = ["us-east-1a"] }
    subnets = {
      app = { role = "private", ipv4 = { cidrs_by_az = { us-east-1a = "10.132.0.0/24" } } }
    }
    routes = {
      invalid = {
        from_group  = "app"
        destination = { type = "ipv4_cidr", value = "0.0.0.0/0" }
        target      = { type = "vpc_endpoint", id = "vpce-static", ids_by_az = { us-east-1a = "vpce-a" } }
      }
    }
  }

  expect_failures = [var.routes]
}

run "reject_top_level_target_with_neither_id_form" {
  command = plan

  variables {
    vpc                = { name = "xor-neither" }
    addressing         = { primary = { cidr_block = "10.133.0.0/16" } }
    availability_zones = { names = ["us-east-1a"] }
    subnets = {
      app = { role = "private", ipv4 = { cidrs_by_az = { us-east-1a = "10.133.0.0/24" } } }
    }
    routes = {
      invalid = {
        from_group  = "app"
        destination = { type = "ipv4_cidr", value = "0.0.0.0/0" }
        target      = { type = "vpc_endpoint" }
      }
    }
  }

  expect_failures = [var.routes]
}

run "reject_unknown_top_level_from_group" {
  command = plan

  variables {
    vpc                = { name = "unknown-group" }
    addressing         = { primary = { cidr_block = "10.134.0.0/16" } }
    availability_zones = { names = ["us-east-1a"] }
    subnets = {
      app = { role = "private", ipv4 = { cidrs_by_az = { us-east-1a = "10.134.0.0/24" } } }
    }
    routes = {
      invalid = {
        from_group  = "missing"
        destination = { type = "ipv4_cidr", value = "0.0.0.0/0" }
        target      = { type = "vpc_endpoint", id = "vpce-static" }
      }
    }
  }

  expect_failures = [terraform_data.top_level_routes_validation]
}

run "reject_zonal_target_missing_group_az" {
  command = plan

  variables {
    vpc                = { name = "missing-az" }
    addressing         = { primary = { cidr_block = "10.135.0.0/16" } }
    availability_zones = { names = ["us-east-1a", "us-east-1b"] }
    subnets = {
      app = {
        role = "private"
        ipv4 = { cidrs_by_az = { us-east-1a = "10.135.0.0/24", us-east-1b = "10.135.1.0/24" } }
      }
    }
    routes = {
      invalid = {
        from_group  = "app"
        destination = { type = "ipv4_cidr", value = "0.0.0.0/0" }
        target      = { type = "vpc_endpoint", ids_by_az = { us-east-1a = "vpce-a" } }
      }
    }
  }

  expect_failures = [terraform_data.top_level_routes_validation]
}

run "reject_cross_surface_destination_collision" {
  command = plan

  variables {
    vpc                = { name = "cross-surface-collision" }
    addressing         = { primary = { cidr_block = "10.136.0.0/16" } }
    availability_zones = { names = ["us-east-1a"] }
    subnets = {
      app = {
        role = "private"
        ipv4 = { cidrs_by_az = { us-east-1a = "10.136.0.0/24" } }
        routes = {
          legacy = {
            destination = { type = "ipv4_cidr", value = "10.200.0.0/16" }
            target      = { type = "vpc_peering", id = "pcx-documentation" }
          }
        }
      }
    }
    routes = {
      late-bound = {
        from_group  = "app"
        destination = { type = "ipv4_cidr", value = "10.200.0.0/16" }
        target      = { type = "vpc_endpoint", id = "vpce-static" }
      }
    }
  }

  expect_failures = [terraform_data.route_table_routing_compatibility_validation]
}

run "reject_two_top_level_routes_for_one_destination" {
  command = plan

  variables {
    vpc                = { name = "top-level-collision" }
    addressing         = { primary = { cidr_block = "10.137.0.0/16" } }
    availability_zones = { names = ["us-east-1a"] }
    subnets = {
      app = { role = "private", ipv4 = { cidrs_by_az = { us-east-1a = "10.137.0.0/24" } } }
    }
    routes = {
      first = {
        from_group  = "app"
        destination = { type = "ipv4_cidr", value = "10.200.0.0/16" }
        target      = { type = "vpc_endpoint", id = "vpce-first" }
      }
      second = {
        from_group  = "app"
        destination = { type = "ipv4_cidr", value = "10.200.0.0/16" }
        target      = { type = "vpc_endpoint", id = "vpce-second" }
      }
    }
  }

  expect_failures = [terraform_data.route_table_routing_compatibility_validation]
}

run "reject_top_level_route_key_with_slash" {
  command = plan

  variables {
    vpc                = { name = "slash-key" }
    addressing         = { primary = { cidr_block = "10.138.0.0/16" } }
    availability_zones = { names = ["us-east-1a"] }
    subnets = {
      app = { role = "private", ipv4 = { cidrs_by_az = { us-east-1a = "10.138.0.0/24" } } }
    }
    routes = {
      "invalid/key" = {
        from_group  = "app"
        destination = { type = "ipv4_cidr", value = "0.0.0.0/0" }
        target      = { type = "vpc_endpoint", id = "vpce-static" }
      }
    }
  }

  expect_failures = [var.routes]
}

run "reject_top_level_route_for_isolated_group" {
  command = plan

  variables {
    vpc                = { name = "isolated-top-level" }
    addressing         = { primary = { cidr_block = "10.139.0.0/16" } }
    availability_zones = { names = ["us-east-1a"] }
    subnets = {
      data = { role = "isolated", ipv4 = { cidrs_by_az = { us-east-1a = "10.139.0.0/24" } } }
    }
    routes = {
      invalid = {
        from_group  = "data"
        destination = { type = "prefix_list", value = "pl-0123456789abcdef0" }
        target      = { type = "vpc_endpoint", id = "vpce-static" }
      }
    }
  }

  expect_failures = [terraform_data.top_level_routes_validation]
}
