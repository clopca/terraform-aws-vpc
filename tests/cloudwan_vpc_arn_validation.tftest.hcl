# Test: var.vpc_arn validation rejects invalid ARN formats.
# This catches the regression from issue #162 where vpc_arn was not
# user-overridable and the data source lookup caused spurious replacements.

run "reject_invalid_vpc_arn" {
  command = plan

  variables {
    name       = "test-cwan-arn"
    cidr_block = "10.0.0.0/16"
    az_count   = 2
    vpc_arn    = "not-a-valid-arn"
    subnets = {
      private = { netmask = 24 }
    }
  }

  expect_failures = [var.vpc_arn]
}

run "accept_null_vpc_arn" {
  command = plan

  variables {
    name       = "test-cwan-arn"
    cidr_block = "10.0.0.0/16"
    az_count   = 2
    vpc_arn    = null
    subnets = {
      private = { netmask = 24 }
    }
  }
}
