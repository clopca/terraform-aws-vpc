mock_provider "aws" {
  mock_resource "aws_vpc" {
    defaults = {
      id  = "vpc-mock"
      arn = "arn:aws:ec2:us-east-1:123456789012:vpc/vpc-mock"
    }
  }

  mock_resource "aws_subnet" {
    defaults = {
      id  = "subnet-mock"
      arn = "arn:aws:ec2:us-east-1:123456789012:subnet/subnet-mock"
    }
  }

  mock_resource "aws_route_table" {
    defaults = {
      id = "rtb-mock"
    }
  }
}

run "unpinned_before_group_add" {
  command = plan

  variables {
    vpc                = { name = "cidr-test" }
    addressing         = { ipv4 = { cidr_block = "10.0.0.0/16" } }
    availability_zones = { names = ["us-east-1a", "us-east-1b"] }
    subnets = {
      alpha = { role = "private", ipv4 = { netmask = 24 } }
      gamma = { role = "private", ipv4 = { netmask = 24 } }
    }
  }

  assert {
    condition = (
      keys(output.subnet_cidrs_by_group_by_az) == ["alpha", "gamma"] && alltrue([
        keys(output.subnet_cidrs_by_group_by_az.alpha) == ["us-east-1a", "us-east-1b"],
        keys(output.subnet_cidrs_by_group_by_az.gamma) == ["us-east-1a", "us-east-1b"],
      ])
    )
    error_message = "Unpinned subnet keys must be exact and AZ-nested."
  }

  assert {
    condition = (
      output.subnet_cidrs_by_group_by_az == {
        alpha = { us-east-1a = "10.0.0.0/24", us-east-1b = "10.0.1.0/24" }
        gamma = { us-east-1a = "10.0.6.0/24", us-east-1b = "10.0.7.0/24" }
      }
    )
    error_message = "The baseline unpinned CIDR allocation changed."
  }
}

run "unpinned_after_group_add" {
  command = plan

  variables {
    vpc                = { name = "cidr-test" }
    addressing         = { ipv4 = { cidr_block = "10.0.0.0/16" } }
    availability_zones = { names = ["us-east-1a", "us-east-1b"] }
    subnets = {
      alpha = { role = "private", ipv4 = { netmask = 24 } }
      beta  = { role = "private", ipv4 = { netmask = 24 } }
      gamma = { role = "private", ipv4 = { netmask = 24 } }
    }
  }

  assert {
    condition     = keys(output.subnet_cidrs_by_group_by_az) == ["alpha", "beta", "gamma"]
    error_message = "Adding an unpinned group must add exactly that group key."
  }

  assert {
    condition = (
      output.subnet_cidrs_by_group_by_az == {
        alpha = { us-east-1a = "10.0.0.0/24", us-east-1b = "10.0.1.0/24" }
        beta  = { us-east-1a = "10.0.6.0/24", us-east-1b = "10.0.7.0/24" }
        gamma = { us-east-1a = "10.0.12.0/24", us-east-1b = "10.0.13.0/24" }
      }
    )
    error_message = "Unpinned groups that sort after an insertion must shift deterministically."
  }
}

run "unpinned_after_group_remove" {
  command = plan

  variables {
    vpc                = { name = "cidr-test" }
    addressing         = { ipv4 = { cidr_block = "10.0.0.0/16" } }
    availability_zones = { names = ["us-east-1a", "us-east-1b"] }
    subnets = {
      alpha = { role = "private", ipv4 = { netmask = 24 } }
      gamma = { role = "private", ipv4 = { netmask = 24 } }
    }
  }

  assert {
    condition     = keys(output.subnet_cidrs_by_group_by_az) == ["alpha", "gamma"]
    error_message = "Removing an unpinned group must remove exactly that group key."
  }

  assert {
    condition = (
      output.subnet_cidrs_by_group_by_az == {
        alpha = { us-east-1a = "10.0.0.0/24", us-east-1b = "10.0.1.0/24" }
        gamma = { us-east-1a = "10.0.6.0/24", us-east-1b = "10.0.7.0/24" }
      }
    )
    error_message = "Removing an earlier unpinned group must compact later groups deterministically."
  }
}

run "pinned_before_group_add" {
  command = plan

  variables {
    vpc                = { name = "cidr-test" }
    addressing         = { ipv4 = { cidr_block = "10.0.0.0/16" } }
    availability_zones = { names = ["us-east-1a", "us-east-1b"] }
    subnets = {
      alpha = { role = "private", ipv4 = { netmask = 24, cidr_index = 0 } }
      gamma = { role = "private", ipv4 = { netmask = 24, cidr_index = 5 } }
    }
  }

  assert {
    condition     = keys(output.subnet_cidrs_by_group_by_az) == ["alpha", "gamma"]
    error_message = "Pinned baseline keys must be exact."
  }

  assert {
    condition = (
      output.subnet_cidrs_by_group_by_az == {
        alpha = { us-east-1a = "10.0.0.0/24", us-east-1b = "10.0.1.0/24" }
        gamma = { us-east-1a = "10.0.30.0/24", us-east-1b = "10.0.31.0/24" }
      }
    )
    error_message = "Pinned CIDR slots must reserve six AZ positions per group."
  }
}

run "pinned_after_group_add" {
  command = plan

  variables {
    vpc                = { name = "cidr-test" }
    addressing         = { ipv4 = { cidr_block = "10.0.0.0/16" } }
    availability_zones = { names = ["us-east-1a", "us-east-1b"] }
    subnets = {
      alpha = { role = "private", ipv4 = { netmask = 24, cidr_index = 0 } }
      beta  = { role = "private", ipv4 = { netmask = 24 } }
      gamma = { role = "private", ipv4 = { netmask = 24, cidr_index = 5 } }
    }
  }

  assert {
    condition     = keys(output.subnet_cidrs_by_group_by_az) == ["alpha", "beta", "gamma"]
    error_message = "Adding an unpinned group beside pinned groups must add exactly one key."
  }

  assert {
    condition = (
      output.subnet_cidrs_by_group_by_az == {
        alpha = { us-east-1a = "10.0.0.0/24", us-east-1b = "10.0.1.0/24" }
        beta  = { us-east-1a = "10.0.36.0/24", us-east-1b = "10.0.37.0/24" }
        gamma = { us-east-1a = "10.0.30.0/24", us-east-1b = "10.0.31.0/24" }
      }
    )
    error_message = "Adding an unpinned group must not move pinned groups."
  }
}

run "pinned_after_group_remove" {
  command = plan

  variables {
    vpc                = { name = "cidr-test" }
    addressing         = { ipv4 = { cidr_block = "10.0.0.0/16" } }
    availability_zones = { names = ["us-east-1a", "us-east-1b"] }
    subnets = {
      alpha = { role = "private", ipv4 = { netmask = 24, cidr_index = 0 } }
      gamma = { role = "private", ipv4 = { netmask = 24, cidr_index = 5 } }
    }
  }

  assert {
    condition     = keys(output.subnet_cidrs_by_group_by_az) == ["alpha", "gamma"]
    error_message = "Removing an unpinned group from a pinned layout must remove exactly one key."
  }

  assert {
    condition = (
      output.subnet_cidrs_by_group_by_az == {
        alpha = { us-east-1a = "10.0.0.0/24", us-east-1b = "10.0.1.0/24" }
        gamma = { us-east-1a = "10.0.30.0/24", us-east-1b = "10.0.31.0/24" }
      }
    )
    error_message = "Removing an unpinned group must not move pinned groups."
  }
}

run "add_availability_zone" {
  command = plan

  variables {
    vpc                = { name = "cidr-test" }
    addressing         = { ipv4 = { cidr_block = "10.0.0.0/16" } }
    availability_zones = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
    subnets = {
      alpha = { role = "private", ipv4 = { netmask = 24 } }
      gamma = { role = "private", ipv4 = { netmask = 24 } }
    }
  }

  assert {
    condition = (
      alltrue([
        keys(output.subnet_cidrs_by_group_by_az.alpha) == ["us-east-1a", "us-east-1b", "us-east-1c"],
        keys(output.subnet_cidrs_by_group_by_az.gamma) == ["us-east-1a", "us-east-1b", "us-east-1c"],
      ])
    )
    error_message = "Adding an AZ must append exactly one nested AZ key per group."
  }

  assert {
    condition = (
      output.subnet_cidrs_by_group_by_az == {
        alpha = { us-east-1a = "10.0.0.0/24", us-east-1b = "10.0.1.0/24", us-east-1c = "10.0.2.0/24" }
        gamma = { us-east-1a = "10.0.6.0/24", us-east-1b = "10.0.7.0/24", us-east-1c = "10.0.8.0/24" }
      }
    )
    error_message = "Adding an AZ must preserve existing AZ CIDRs and consume the reserved next slot."
  }
}

run "explicit_cidrs" {
  command = plan

  variables {
    vpc                = { name = "cidr-test" }
    addressing         = { ipv4 = { cidr_block = "10.0.0.0/16" } }
    availability_zones = { names = ["us-east-1a", "us-east-1b"] }
    subnets = {
      app = {
        role = "private"
        ipv4 = { cidrs = ["10.0.100.0/24", "10.0.200.0/24"] }
      }
    }
  }

  assert {
    condition = (
      keys(output.subnet_cidrs_by_group_by_az) == ["app"] &&
      keys(output.subnet_cidrs_by_group_by_az.app) == ["us-east-1a", "us-east-1b"]
    )
    error_message = "Explicit CIDR output keys must match the group and configured AZs exactly."
  }

  assert {
    condition = (
      output.subnet_cidrs_by_group_by_az.app == {
        us-east-1a = "10.0.100.0/24"
        us-east-1b = "10.0.200.0/24"
      }
    )
    error_message = "Explicit CIDRs must pass through unchanged in AZ order."
  }
}

run "mixed_netmasks_pack_without_overlap" {
  command = plan

  variables {
    vpc                = { name = "cidr-test" }
    addressing         = { ipv4 = { cidr_block = "10.0.0.0/16" } }
    availability_zones = { names = ["us-east-1a", "us-east-1b"] }
    subnets = {
      application = { role = "private", ipv4 = { netmask = 22 } }
      public      = { role = "public", ipv4 = { netmask = 24 } }
    }
  }

  assert {
    condition = (
      toset(keys(output.subnet_cidrs_by_group_by_az)) == toset(["application", "public"])
    )
    error_message = "Mixed-netmask allocation must retain both exact group keys."
  }

  assert {
    condition = (
      output.subnet_cidrs_by_group_by_az == {
        application = { us-east-1a = "10.0.0.0/22", us-east-1b = "10.0.4.0/22" }
        public      = { us-east-1a = "10.0.24.0/24", us-east-1b = "10.0.25.0/24" }
      }
    )
    error_message = "Mixed netmasks must pack largest-first without overlapping their six-AZ reservations."
  }
}
