run "validate" {
  command = apply
  module {
    source = "./examples/ipam"
  }

  # VPC created (IPAM assigns CIDR dynamically, just verify it got one)
  assert {
    condition     = module.vpc.vpc_attributes.cidr_block != ""
    error_message = "VPC should have a CIDR block assigned by IPAM"
  }

  # VPC ID format
  assert {
    condition     = can(regex("^vpc-[0-9a-f]+$", module.vpc.vpc_attributes.id))
    error_message = "VPC ID should match vpc-* format"
  }

  # AZs assigned
  assert {
    condition     = length(module.vpc.azs) >= 2
    error_message = "Expected at least 2 AZs"
  }

  # Private subnets created
  assert {
    condition     = length(module.vpc.private_subnet_attributes_by_az) >= 2
    error_message = "Expected at least 2 private subnets"
  }
}
