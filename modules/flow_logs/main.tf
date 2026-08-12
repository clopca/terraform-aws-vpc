locals {
  # does log destination need to be created?
  create_flow_log_destination = (var.flow_log_definition.log_destination == null && var.flow_log_definition.log_destination_type != "none") ? true : false

  # which log destination to use
  log_destination = local.create_flow_log_destination ? (
    var.flow_log_definition.log_destination_type == "cloud-watch-logs" ? aws_cloudwatch_log_group.main[0].arn : module.s3_log_bucket[0].bucket_flow_logs_attributes.arn
  ) : var.flow_log_definition.log_destination

  # Use IAM from inline resources if not passed
  iam_role_arn = local.create_flow_log_destination ? (
    var.flow_log_definition.log_destination_type == "cloud-watch-logs" ? aws_iam_role.flow_logs[0].arn : null
  ) : var.flow_log_definition.iam_role_arn

  # Helper locals for naming
  cw_name_prefix = "${var.name}-vpc-flow-logs-"
}

# --- CloudWatch Log Group (replaces aws-ia/cloudwatch-log-group module) ---

resource "aws_cloudwatch_log_group" "main" {
  count = (local.create_flow_log_destination && var.flow_log_definition.log_destination_type == "cloud-watch-logs") ? 1 : 0

  name_prefix       = local.cw_name_prefix
  retention_in_days = var.flow_log_definition.retention_in_days == null ? 180 : var.flow_log_definition.retention_in_days
  kms_key_id        = var.flow_log_definition.kms_key_id
  tags              = var.tags
}

resource "aws_iam_role" "flow_logs" {
  count = (local.create_flow_log_destination && var.flow_log_definition.log_destination_type == "cloud-watch-logs") ? 1 : 0

  name_prefix = "${var.name}-cw-access-role-"
  description = "CloudWatch Logs access role for ${var.name} VPC flow logs"
  tags        = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "VpcFlowLogsCloudwatchTrust"
        Effect    = "Allow"
        Principal = { Service = "vpc-flow-logs.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = (local.create_flow_log_destination && var.flow_log_definition.log_destination_type == "cloud-watch-logs") ? 1 : 0

  name_prefix = "${var.name}-cw-access-"
  role        = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "FlowLogsToCW"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
        ]
        Resource = "*" #tfsec:ignore:aws-iam-no-policy-wildcards
      }
    ]
  })
}

# --- S3 Log Bucket (unchanged) ---

module "s3_log_bucket" {
  # if create destination and type = s3
  count  = (local.create_flow_log_destination && var.flow_log_definition.log_destination_type == "s3") ? 1 : 0
  source = "./modules/s3_log_bucket"

  name                    = var.name
  lifecycle_filter_prefix = var.log_bucket_lifecycle_filter_prefix
}

# --- Flow Log resource ---

resource "aws_flow_log" "main" {
  log_destination      = local.log_destination
  iam_role_arn         = local.iam_role_arn
  log_destination_type = var.flow_log_definition.log_destination_type
  traffic_type         = var.flow_log_definition.traffic_type
  vpc_id               = var.vpc_id
  log_format           = var.flow_log_definition.log_format
  dynamic "destination_options" {
    for_each = var.flow_log_definition.log_destination_type == "s3" ? [true] : []

    content {
      file_format                = var.flow_log_definition.destination_options.file_format
      per_hour_partition         = var.flow_log_definition.destination_options.per_hour_partition
      hive_compatible_partitions = var.flow_log_definition.destination_options.hive_compatible_partitions
    }
  }

  tags = merge(
    { Name = var.name },
    var.tags
  )
}
