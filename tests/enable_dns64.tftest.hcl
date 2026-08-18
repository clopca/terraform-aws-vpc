# Regression test for aws-ia/terraform-aws-vpc#176 (comment-5197372581):
# `enable_dns64` must be configurable per subnet and reach the aws_subnet resource.
# Uses a mock provider + deterministic AZ data so it runs offline in CI.

mock_provider "aws" {}

override_data {
  target = data.aws_availability_zones.current
  values = {
    names = ["us-east-1a", "us-east-1b"]
  }
}

# enable_dns64 = true propagates to public and private (incl. IPv6-only) subnets,
# and defaults to false when the key is omitted.
run "dns64_enabled_when_set" {
  command = plan

  variables {
    name       = "dns64-test"
    cidr_block = "10.0.0.0/16"
    az_count   = 2

    vpc_assign_generated_ipv6_cidr_block = true
    vpc_egress_only_internet_gateway     = true

    subnets = {
      public = {
        netmask          = 24
        assign_ipv6_cidr = true
        enable_dns64     = true
      }
      private_ipv6_only = {
        assign_ipv6_cidr = true
        ipv6_native      = true
        connect_to_eigw  = true
        enable_dns64     = true
      }
      private_plain = {
        netmask = 24
      }
    }
  }

  assert {
    condition     = alltrue([for az, s in aws_subnet.public : s.enable_dns64 == true])
    error_message = "enable_dns64=true was not propagated to public subnets"
  }

  assert {
    condition     = aws_subnet.private["private_ipv6_only/us-east-1a"].enable_dns64 == true
    error_message = "enable_dns64=true was not propagated to the IPv6-only private subnet"
  }

  assert {
    condition     = aws_subnet.private["private_plain/us-east-1a"].enable_dns64 == false
    error_message = "private subnet without enable_dns64 must default to false"
  }
}

# When enable_dns64 is not set anywhere, every subnet keeps the AWS default (false).
run "dns64_defaults_false" {
  command = plan

  variables {
    name       = "dns64-default-test"
    cidr_block = "10.0.0.0/16"
    az_count   = 2

    subnets = {
      public = {
        netmask = 24
      }
      private_plain = {
        netmask = 24
      }
    }
  }

  assert {
    condition     = alltrue([for az, s in aws_subnet.public : s.enable_dns64 == false])
    error_message = "public subnets must default enable_dns64 to false"
  }

  assert {
    condition     = alltrue([for k, s in aws_subnet.private : s.enable_dns64 == false])
    error_message = "private subnets must default enable_dns64 to false"
  }
}
