run "validate" {
  command = apply
  module {
    source = "./examples/advanced"
  }

  # Primary VPC CIDR
  assert {
    condition     = module.vpc.vpc_attributes.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR block should be 10.0.0.0/16"
  }

  # Explicit AZs (eu-west-1a, eu-west-1c)
  assert {
    condition     = length(module.vpc.azs) == 2
    error_message = "Expected 2 AZs"
  }

  # Public subnets (1 per AZ)
  assert {
    condition     = length(module.vpc.public_subnet_attributes_by_az) == 2
    error_message = "Expected 2 public subnets"
  }

  # NAT gateway (single_az = only 1 NAT)
  assert {
    condition     = length(module.vpc.nat_gateway_attributes_by_az) == 1
    error_message = "Expected 1 NAT gateway (single_az mode)"
  }

  # Private subnets created (private + database + infrastructure = 3 types × 2 AZs = 6)
  assert {
    condition     = length(module.vpc.private_subnet_attributes_by_az) == 6
    error_message = "Expected 6 private subnets (3 types × 2 AZs)"
  }

  # Flow logs created (S3 destination)
  assert {
    condition     = module.vpc.flow_log_attributes != null
    error_message = "Flow logs should be created"
  }

  # Secondary CIDR VPC uses existing VPC
  assert {
    condition     = module.secondary_cidr_block.vpc_attributes.id == module.vpc.vpc_attributes.id
    error_message = "Secondary CIDR should attach to the primary VPC"
  }

  # Secondary CIDR private subnets (1 AZ only)
  assert {
    condition     = length(module.secondary_cidr_block.private_subnet_attributes_by_az) == 1
    error_message = "Secondary CIDR should have 1 private subnet (1 AZ)"
  }
}
