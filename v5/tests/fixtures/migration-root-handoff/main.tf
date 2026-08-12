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
