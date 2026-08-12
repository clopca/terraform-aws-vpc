mock_provider "aws" {
  override_during = plan
  mock_resource "aws_vpc" {
    defaults = {
      id         = "vpc-mock"
      arn        = "arn:aws:ec2:us-east-1:123456789012:vpc/vpc-mock"
      cidr_block = "10.0.0.0/16"
    }
  }

  mock_resource "aws_vpc_ipv4_cidr_block_association" {
    defaults = { id = "vpc-cidr-assoc-mock" }
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
}

run "secondary_static_and_ipam_are_stable" {
  command = plan

  variables {
    vpc = { name = "secondary-test" }
    addressing = {
      ipv4 = {
        cidr_block = "10.0.0.0/16"
        secondary = {
          analytics = {
            ipam_pool_id   = "ipam-pool-0123456789abcdef0"
            netmask_length = 20
          }
          shared-services = {
            cidr_block = "100.64.0.0/20"
          }
        }
      }
    }
    availability_zones = { names = ["us-east-1a", "us-east-1b"] }
    subnets = {
      analytics = {
        role = "private"
        ipv4 = {
          ipam_pool_id       = "ipam-pool-0123456789abcdef0"
          netmask_length     = 24
          secondary_cidr_key = "analytics"
        }
      }
      shared = {
        role = "private"
        ipv4 = {
          cidrs              = ["100.64.0.0/24", "100.64.1.0/24"]
          secondary_cidr_key = "shared-services"
        }
      }
    }
  }

  assert {
    condition = (
      toset(keys(aws_vpc_ipv4_cidr_block_association.secondary)) == toset(["analytics", "shared-services"]) &&
      aws_vpc_ipv4_cidr_block_association.secondary["analytics"].ipv4_ipam_pool_id == "ipam-pool-0123456789abcdef0" &&
      aws_vpc_ipv4_cidr_block_association.secondary["analytics"].ipv4_netmask_length == 20 &&
      aws_vpc_ipv4_cidr_block_association.secondary["shared-services"].cidr_block == "100.64.0.0/20" &&
      toset(keys(output.secondary_cidr_association_ids)) == toset(["analytics", "shared-services"])
    )
    error_message = "Secondary CIDR state identities must come from caller-owned keys and preserve static/IPAM arguments."
  }

  assert {
    condition = (
      aws_subnet.main["analytics/us-east-1a"].ipv4_ipam_pool_id == "ipam-pool-0123456789abcdef0" &&
      aws_subnet.main["analytics/us-east-1a"].ipv4_netmask_length == 24 &&
      aws_subnet.main["shared/us-east-1a"].cidr_block == "100.64.0.0/24" &&
      aws_subnet.main["shared/us-east-1b"].cidr_block == "100.64.1.0/24"
    )
    error_message = "Subnets selecting secondary associations must retain their planned IPAM/static attributes."
  }
}

run "inject_secondary_association" {
  command = plan

  variables {
    vpc = { name = "secondary-inject-test" }
    addressing = {
      ipv4 = {
        cidr_block = "10.0.0.0/16"
        secondary = {
          adopted = {
            create         = false
            association_id = "vpc-cidr-assoc-0123456789abcdef0"
          }
        }
      }
    }
    availability_zones = { names = ["us-east-1a"] }
    subnets = {
      adopted = {
        role = "private"
        ipv4 = {
          cidrs              = ["100.64.10.0/24"]
          secondary_cidr_key = "adopted"
        }
      }
    }
  }

  assert {
    condition = (
      length(aws_vpc_ipv4_cidr_block_association.secondary) == 0 &&
      output.secondary_cidr_association_ids.adopted == "vpc-cidr-assoc-0123456789abcdef0" &&
      aws_subnet.main["adopted/us-east-1a"].cidr_block == "100.64.10.0/24"
    )
    error_message = "Injected secondary associations must omit resource creation and remain selectable by subnets."
  }
}

run "reject_secondary_with_two_sources" {
  command = plan

  variables {
    vpc = { name = "negative-test" }
    addressing = {
      ipv4 = {
        cidr_block = "10.0.0.0/16"
        secondary = {
          invalid = {
            cidr_block     = "100.64.0.0/20"
            ipam_pool_id   = "ipam-pool-0123456789abcdef0"
            netmask_length = 20
          }
        }
      }
    }
    availability_zones = { names = ["us-east-1a"] }
    subnets            = {}
  }

  expect_failures = [var.addressing]
}

run "reject_unknown_secondary_selector" {
  command = plan

  variables {
    vpc                = { name = "negative-test" }
    addressing         = { ipv4 = { cidr_block = "10.0.0.0/16" } }
    availability_zones = { names = ["us-east-1a"] }
    subnets = {
      app = {
        role = "private"
        ipv4 = {
          cidrs              = ["10.0.0.0/24"]
          secondary_cidr_key = "missing"
        }
      }
    }
  }

  expect_failures = [terraform_data.subnet_secondary_cidr_validation["app/us-east-1a"]]
}
