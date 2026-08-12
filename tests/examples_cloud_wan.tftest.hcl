run "validate" {
  command = apply
  module {
    source = "./examples/cloud_wan"
  }

  # N.Virginia VPC CIDR
  assert {
    condition     = module.nvirginia_vpc.vpc_attributes.cidr_block == "10.0.0.0/24"
    error_message = "N.Virginia VPC CIDR should be 10.0.0.0/24"
  }

  # Ireland VPC CIDR
  assert {
    condition     = module.ireland_vpc.vpc_attributes.cidr_block == "10.0.1.0/24"
    error_message = "Ireland VPC CIDR should be 10.0.1.0/24"
  }

  # Core network attachments created
  assert {
    condition     = module.nvirginia_vpc.core_network_attachment != null
    error_message = "N.Virginia should have a Core Network attachment"
  }

  assert {
    condition     = module.ireland_vpc.core_network_attachment != null
    error_message = "Ireland should have a Core Network attachment"
  }

  # Core network subnets created (2 AZs each)
  assert {
    condition     = length(module.nvirginia_vpc.core_network_subnet_attributes_by_az) == 2
    error_message = "Expected 2 core network subnets in N.Virginia"
  }

  assert {
    condition     = length(module.ireland_vpc.core_network_subnet_attributes_by_az) == 2
    error_message = "Expected 2 core network subnets in Ireland"
  }
}
