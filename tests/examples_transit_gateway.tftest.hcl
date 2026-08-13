run "validate" {
  command = apply
  module {
    source = "./examples/transit_gateway"
  }

  # VPC CIDR
  assert {
    condition     = module.vpc.vpc_attributes.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR block should be 10.0.0.0/16"
  }

  # 2 AZs
  assert {
    condition     = length(module.vpc.azs) == 2
    error_message = "Expected 2 AZs"
  }

  # TGW attachment created
  assert {
    condition     = module.vpc.transit_gateway_attachment_id != null
    error_message = "Transit Gateway attachment should be created"
  }

  # TGW attachment ID format
  assert {
    condition     = can(regex("^tgw-attach-[0-9a-f]+$", module.vpc.transit_gateway_attachment_id))
    error_message = "TGW attachment ID should match tgw-attach-* format"
  }

  # TGW subnets created (1 per AZ)
  assert {
    condition     = length(module.vpc.tgw_subnet_attributes_by_az) == 2
    error_message = "Expected 2 TGW subnets"
  }

  # Private subnets created
  assert {
    condition     = length(module.vpc.private_subnet_attributes_by_az) >= 2
    error_message = "Expected at least 2 private subnets"
  }

  # Route tables include transit_gateway type
  assert {
    condition     = length(module.vpc.rt_attributes_by_type_by_az.transit_gateway) == 2
    error_message = "Expected 2 TGW route tables"
  }
}
