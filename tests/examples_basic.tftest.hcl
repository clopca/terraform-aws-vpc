run "validate" {
  command = apply
  module {
    source = "./examples/basic"
  }

  # VPC was created with correct CIDR
  assert {
    condition     = module.vpc.vpc_attributes.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR block should be 10.0.0.0/16"
  }

  # IPv6 CIDR was assigned
  assert {
    condition     = module.vpc.vpc_attributes.ipv6_association_id != ""
    error_message = "VPC should have an IPv6 CIDR association"
  }

  # Correct number of AZs (az_count = 2)
  assert {
    condition     = length(module.vpc.azs) == 2
    error_message = "Expected 2 AZs"
  }

  # Public subnets created (1 per AZ)
  assert {
    condition     = length(module.vpc.public_subnet_attributes_by_az) == 2
    error_message = "Expected 2 public subnets"
  }

  # Private subnets created (multiple types × 2 AZs)
  assert {
    condition     = length(module.vpc.private_subnet_attributes_by_az) >= 2
    error_message = "Expected at least 2 private subnets"
  }

  # NAT gateways created (all_azs = one per AZ)
  assert {
    condition     = length(module.vpc.nat_gateway_attributes_by_az) == 2
    error_message = "Expected 2 NAT gateways (all_azs mode)"
  }

  # EIGW created
  assert {
    condition     = module.vpc.egress_only_internet_gateway != null
    error_message = "Egress-only internet gateway should be created"
  }

  # Flow logs created
  assert {
    condition     = module.vpc.flow_log_attributes != null
    error_message = "Flow logs should be created"
  }

  # VPC ID format
  assert {
    condition     = can(regex("^vpc-[0-9a-f]+$", module.vpc.vpc_attributes.id))
    error_message = "VPC ID should match vpc-* format"
  }
}
