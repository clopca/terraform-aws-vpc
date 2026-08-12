run "validate" {
  command = apply
  module {
    source = "./examples/vpc_lattice"
  }

  # VPC CIDR
  assert {
    condition     = module.vpc.vpc_attributes.cidr_block == "10.0.0.0/24"
    error_message = "VPC CIDR block should be 10.0.0.0/24"
  }

  # 2 AZs
  assert {
    condition     = length(module.vpc.azs) == 2
    error_message = "Expected 2 AZs"
  }

  # VPC Lattice association created
  assert {
    condition     = module.vpc.vpc_lattice_service_network_association != null
    error_message = "VPC Lattice service network association should be created"
  }

  # VPC ID format
  assert {
    condition     = can(regex("^vpc-[0-9a-f]+$", module.vpc.vpc_attributes.id))
    error_message = "VPC ID should match vpc-* format"
  }

  # Private subnets created (workload × 2 AZs)
  assert {
    condition     = length(module.vpc.private_subnet_attributes_by_az) == 2
    error_message = "Expected 2 private (workload) subnets"
  }
}
