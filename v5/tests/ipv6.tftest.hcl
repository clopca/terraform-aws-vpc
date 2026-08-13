mock_provider "aws" {
  override_during = plan
  mock_resource "aws_vpc" {
    defaults = {
      id              = "vpc-mock"
      arn             = "arn:aws:ec2:us-east-1:123456789012:vpc/vpc-mock"
      cidr_block      = "10.0.0.0/16"
      ipv6_cidr_block = "2600:1f18:4200::/56"
    }
  }

  mock_resource "aws_subnet" {
    defaults = {
      id  = "subnet-mock"
      arn = "arn:aws:ec2:us-east-1:123456789012:subnet/subnet-mock"
    }
  }

  mock_resource "aws_route_table" {
    defaults = { id = "rtb-mock" }
  }

  mock_resource "aws_nat_gateway" {
    defaults = { id = "nat-mock" }
  }

  mock_resource "aws_egress_only_internet_gateway" {
    defaults = { id = "eigw-mock" }
  }
}

run "generated_dual_stack_dns64_eigw" {
  command = plan

  variables {
    vpc                = { name = "ipv6-test" }
    addressing         = { ipv4 = { cidr_block = "10.0.0.0/16" }, ipv6 = { amazon_assigned = true } }
    availability_zones = { names = ["us-east-1a", "us-east-1b"] }
    subnets = {
      public = {
        role    = "public"
        ipv4    = { cidrs_by_az = { "us-east-1a" = "10.0.0.0/24", "us-east-1b" = "10.0.1.0/24" } }
        ipv6    = { auto_assign = true, cidr_index = 0 }
        routing = { internet_gateway = true }
      }
      app = {
        role    = "private"
        ipv4    = { cidrs_by_az = { "us-east-1a" = "10.0.10.0/24", "us-east-1b" = "10.0.11.0/24" } }
        ipv6    = { auto_assign = true, cidr_index = 2 }
        routing = { egress_only_igw = true, dns64 = true }
      }
    }
    nat_gateway = {
      mode         = "single_az"
      az           = "us-east-1a"
      create       = false
      existing_ids = { us-east-1a = "nat-0123456789abcdef0" }
    }
  }

  assert {
    condition     = aws_vpc.main[0].assign_generated_ipv6_cidr_block
    error_message = "Amazon-provided IPv6 must set assign_generated_ipv6_cidr_block on the VPC."
  }

  assert {
    condition = (
      aws_subnet.main["public/us-east-1a"].ipv6_cidr_block == "2600:1f18:4200::/64" &&
      aws_subnet.main["public/us-east-1b"].ipv6_cidr_block == "2600:1f18:4200:1::/64" &&
      aws_subnet.main["app/us-east-1a"].ipv6_cidr_block == "2600:1f18:4200:c::/64" &&
      aws_subnet.main["app/us-east-1b"].ipv6_cidr_block == "2600:1f18:4200:d::/64" &&
      alltrue([for subnet in values(aws_subnet.main) : subnet.assign_ipv6_address_on_creation])
    )
    error_message = "auto_assign must plan deterministic, pinned /64s and enable address assignment."
  }

  assert {
    condition = (
      length(aws_route.eigw) == 2 &&
      alltrue([for route in values(aws_route.eigw) : route.destination_ipv6_cidr_block == "::/0"]) &&
      length(aws_route.nat64) == 2 &&
      alltrue([for route in values(aws_route.nat64) : route.destination_ipv6_cidr_block == "64:ff9b::/96"])
    )
    error_message = "EIGW and DNS64 must plan complete ::/0 and NAT64 routes."
  }
}

run "vpc_and_subnet_ipv6_ipam" {
  command = plan

  variables {
    vpc = { name = "ipv6-ipam-test" }
    addressing = {
      ipv4 = { cidr_block = "10.0.0.0/16" }
      ipv6 = { ipam_pool_id = "ipam-pool-vpc", netmask_length = 56 }
    }
    availability_zones = { names = ["us-east-1a"] }
    subnets = {
      application = {
        role = "private"
        ipv4 = { cidrs_by_az = { "us-east-1a" = "10.0.0.0/24" } }
        ipv6 = { ipam_pool_id = "ipam-pool-subnet", netmask_length = 64, auto_assign = true }
      }
    }
  }

  assert {
    condition = (
      aws_vpc.main[0].ipv6_ipam_pool_id == "ipam-pool-vpc" &&
      aws_vpc.main[0].ipv6_netmask_length == 56
    )
    error_message = "VPC IPv6 IPAM must pass pool and netmask without an explicit CIDR."
  }

  assert {
    condition = (
      aws_subnet.main["application/us-east-1a"].ipv6_ipam_pool_id == "ipam-pool-subnet" &&
      aws_subnet.main["application/us-east-1a"].ipv6_netmask_length == 64 &&
      aws_subnet.main["application/us-east-1a"].assign_ipv6_address_on_creation
    )
    error_message = "Subnet IPv6 IPAM attributes must be planned explicitly."
  }
}

run "explicit_vpc_ipv6_ipam_cidr" {
  command = plan

  variables {
    vpc = { name = "ipv6-explicit-test" }
    addressing = {
      ipv4 = { cidr_block = "10.0.0.0/16" }
      ipv6 = { ipam_pool_id = "ipam-pool-vpc", cidr_block = "2001:db8:100::/56" }
    }
    availability_zones = { names = ["us-east-1a"] }
    subnets = {
      native = {
        role = "private"
        ipv6 = { native_only = true, auto_assign = true }
      }
    }
  }

  assert {
    condition = (
      aws_vpc.main[0].ipv6_ipam_pool_id == "ipam-pool-vpc" &&
      aws_vpc.main[0].ipv6_cidr_block == "2001:db8:100::/56" &&
      aws_vpc.main[0].ipv6_netmask_length == null
    )
    error_message = "Explicit VPC IPv6 CIDRs must be passed with their IPAM pool."
  }

  assert {
    condition = (
      aws_subnet.main["native/us-east-1a"].ipv6_native &&
      aws_subnet.main["native/us-east-1a"].ipv6_cidr_block == "2001:db8:100::/64"
    )
    error_message = "IPv6-native subnets must plan a real /64 and no IPv4 CIDR."
  }
}
