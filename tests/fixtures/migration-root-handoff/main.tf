terraform {
  required_version = ">= 1.7"
}

# Terraform Core rejects module instance keys in removed.from. These exact
# unindexed nested-module addresses are the root migration contract.
removed {
  from = module.vpc.module.flow_logs.module.cloudwatch_log_group.aws_cloudwatch_log_group.main

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.vpc.module.flow_logs.module.cloudwatch_log_group.aws_iam_policy.main

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.vpc.module.flow_logs.module.cloudwatch_log_group.aws_iam_role_policy_attachment.main

  lifecycle {
    destroy = false
  }
}

variable "v4_ipv6_association_id" {
  type    = string
  default = "vpc-cidr-assoc-0123456789abcdef0"
}

variable "v4_ipv6_ipam_pool_id" {
  type    = string
  default = null
}

variable "v4_ipv6_netmask_length" {
  type    = number
  default = null
}

locals {
  v4_ipv6_import_id = join(",", compact([
    var.v4_ipv6_association_id,
    var.v4_ipv6_ipam_pool_id,
    var.v4_ipv6_netmask_length == null ? null : tostring(var.v4_ipv6_netmask_length),
  ]))
}

output "v4_ipv6_import_id" {
  value = local.v4_ipv6_import_id
}
