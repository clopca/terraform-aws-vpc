# Regression test for the Cloud WAN VPC attachment options added in v4.8.1
# (from aws-ia/terraform-aws-vpc#176, with corrected defaults):
# - routing_policy_label (top-level)
# - options.dns_support / options.security_group_referencing_support
# Defaults must be null so AWS keeps its own defaults and existing attachments see no diff.

mock_provider "aws" {}
mock_provider "awscc" {}

override_data {
  target = data.aws_availability_zones.current
  values = {
    names = ["us-east-1a", "us-east-1b"]
  }
}

run "cwan_options_set" {
  command = plan

  variables {
    name       = "cwan-options-test"
    cidr_block = "10.0.0.0/16"
    az_count   = 2

    core_network = {
      id  = "core-network-0123456789abcdef0"
      arn = "arn:aws:networkmanager::123456789012:core-network/core-network-0123456789abcdef0"
    }

    subnets = {
      core_network = {
        netmask                            = 28
        routing_policy_label               = "prod-attachments"
        dns_support                        = true
        security_group_referencing_support = false
        appliance_mode_support             = true
      }
      workload = {
        netmask = 24
      }
    }
  }

  assert {
    condition     = aws_networkmanager_vpc_attachment.cwan[0].routing_policy_label == "prod-attachments"
    error_message = "routing_policy_label was not propagated to the Cloud WAN VPC attachment"
  }

  assert {
    condition     = [for o in aws_networkmanager_vpc_attachment.cwan[0].options : o.dns_support][0] == true
    error_message = "dns_support was not propagated to the Cloud WAN VPC attachment options"
  }

  assert {
    condition     = [for o in aws_networkmanager_vpc_attachment.cwan[0].options : o.security_group_referencing_support][0] == false
    error_message = "security_group_referencing_support was not propagated to the Cloud WAN VPC attachment options"
  }

  assert {
    condition     = [for o in aws_networkmanager_vpc_attachment.cwan[0].options : o.appliance_mode_support][0] == true
    error_message = "appliance_mode_support was not propagated to the Cloud WAN VPC attachment options"
  }
}

run "cwan_options_default_to_null" {
  command = plan

  variables {
    name       = "cwan-defaults-test"
    cidr_block = "10.0.0.0/16"
    az_count   = 2

    core_network = {
      id  = "core-network-0123456789abcdef0"
      arn = "arn:aws:networkmanager::123456789012:core-network/core-network-0123456789abcdef0"
    }

    subnets = {
      core_network = {
        netmask = 28
      }
    }
  }

  assert {
    condition     = aws_networkmanager_vpc_attachment.cwan[0].routing_policy_label == null
    error_message = "routing_policy_label must default to null (AWS default preserved)"
  }
}
