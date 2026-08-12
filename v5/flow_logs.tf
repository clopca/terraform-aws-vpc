# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Native VPC Flow Logs (Phase 3)
#
# No external modules and no inline_policy blocks. Every destination and IAM
# role boundary is create-or-inject. User map keys are stable resource identity.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  enabled_flow_logs = {
    for name, cfg in var.flow_logs : name => cfg if cfg.enabled
  }

  cloudwatch_destinations_to_create = {
    for name, cfg in local.enabled_flow_logs : name => cfg
    if cfg.destination_type == "cloudwatch" && cfg.destination_arn == null
  }

  cloudwatch_roles_to_create = {
    for name, cfg in local.enabled_flow_logs : name => cfg
    if cfg.destination_type == "cloudwatch" && cfg.iam_role_arn == null
  }

  s3_destinations_to_create = {
    for name, cfg in local.enabled_flow_logs : name => cfg
    if cfg.destination_type == "s3" && cfg.destination_arn == null
  }

  kinesis_destinations_to_create = {
    for name, cfg in local.enabled_flow_logs : name => cfg
    if cfg.destination_type == "kinesis" && cfg.destination_arn == null
  }

  kinesis_buckets_to_create = {
    for name, cfg in local.kinesis_destinations_to_create : name => cfg
    if cfg.kinesis_options.s3_bucket_arn == null
  }

  kinesis_roles_to_create = {
    for name, cfg in local.kinesis_destinations_to_create : name => cfg
    if cfg.kinesis_options.delivery_role_arn == null
  }

  resource_name_base = replace(var.vpc.name, "/[^A-Za-z0-9_.-]/", "-")

  kinesis_bucket_arns = {
    for name, cfg in local.kinesis_destinations_to_create : name => (
      cfg.kinesis_options.s3_bucket_arn != null
      ? cfg.kinesis_options.s3_bucket_arn
      : aws_s3_bucket.kinesis_flow_logs[name].arn
    )
  }

  kinesis_role_arns = {
    for name, cfg in local.kinesis_destinations_to_create : name => (
      cfg.kinesis_options.delivery_role_arn != null
      ? cfg.kinesis_options.delivery_role_arn
      : aws_iam_role.kinesis_flow_logs[name].arn
    )
  }

  flow_log_destination_arns = {
    for name, cfg in local.enabled_flow_logs : name => (
      cfg.destination_arn != null ? cfg.destination_arn :
      cfg.destination_type == "cloudwatch" ? aws_cloudwatch_log_group.flow_logs[name].arn :
      cfg.destination_type == "s3" ? aws_s3_bucket.flow_logs[name].arn :
      aws_kinesis_firehose_delivery_stream.flow_logs[name].arn
    )
  }

  flow_log_role_arns = {
    for name, cfg in local.enabled_flow_logs : name => (
      cfg.destination_type != "cloudwatch" ? null :
      cfg.iam_role_arn != null ? cfg.iam_role_arn :
      aws_iam_role.flow_logs[name].arn
    )
  }
}

# ─── CloudWatch destination and VPC Flow Logs delivery role ───────────────

resource "aws_cloudwatch_log_group" "flow_logs" {
  for_each = local.cloudwatch_destinations_to_create

  name              = coalesce(each.value.cloudwatch_options.name, "/aws/vpc-flow-logs/${local.resource_name_base}/${each.key}")
  retention_in_days = each.value.cloudwatch_options.retention_in_days
  kms_key_id        = each.value.cloudwatch_options.kms_key_id

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.vpc.name}-${each.key}-flow-logs"
  })
}

resource "aws_iam_role" "flow_logs" {
  for_each = local.cloudwatch_roles_to_create

  name_prefix = substr(coalesce(each.value.role_name_prefix, "${local.resource_name_base}-${each.key}-flow-"), 0, 38)
  description = "Allows VPC Flow Logs to publish ${var.vpc.name}/${each.key} logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  permissions_boundary = each.value.role_permissions_boundary
  tags                 = merge(var.tags, each.value.tags)
}

resource "aws_iam_role_policy" "flow_logs" {
  for_each = local.cloudwatch_roles_to_create

  name = "publish-vpc-flow-logs"
  role = aws_iam_role.flow_logs[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents"
      ]
      Resource = "${local.flow_log_destination_arns[each.key]}:*"
    }]
  })
}

# ─── Native S3 destination ────────────────────────────────────────────────

resource "aws_s3_bucket" "flow_logs" {
  for_each = local.s3_destinations_to_create

  bucket_prefix = substr("vpc-flow-logs-${each.key}-", 0, 37)
  force_destroy = false

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.vpc.name}-${each.key}-flow-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  for_each = local.s3_destinations_to_create

  bucket                  = aws_s3_bucket.flow_logs[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  for_each = local.s3_destinations_to_create

  bucket = aws_s3_bucket.flow_logs[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ─── Native Kinesis Data Firehose destination and S3 sink ────────────────

resource "aws_s3_bucket" "kinesis_flow_logs" {
  for_each = local.kinesis_buckets_to_create

  bucket_prefix = substr("vpc-firehose-${each.key}-", 0, 37)
  force_destroy = false

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.vpc.name}-${each.key}-firehose-flow-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "kinesis_flow_logs" {
  for_each = local.kinesis_buckets_to_create

  bucket                  = aws_s3_bucket.kinesis_flow_logs[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kinesis_flow_logs" {
  for_each = local.kinesis_buckets_to_create

  bucket = aws_s3_bucket.kinesis_flow_logs[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role" "kinesis_flow_logs" {
  for_each = local.kinesis_roles_to_create

  name_prefix = substr(coalesce(each.value.kinesis_options.role_name_prefix, "${local.resource_name_base}-${each.key}-firehose-"), 0, 38)
  description = "Allows Kinesis Data Firehose to deliver ${var.vpc.name}/${each.key} flow logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "firehose.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  permissions_boundary = each.value.kinesis_options.permissions_boundary
  tags                 = merge(var.tags, each.value.tags)
}

resource "aws_iam_role_policy" "kinesis_flow_logs" {
  for_each = local.kinesis_roles_to_create

  name = "deliver-vpc-flow-logs"
  role = aws_iam_role.kinesis_flow_logs[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject"
      ]
      Resource = [
        local.kinesis_bucket_arns[each.key],
        "${local.kinesis_bucket_arns[each.key]}/*"
      ]
    }]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "flow_logs" {
  for_each = local.kinesis_destinations_to_create

  name        = substr(coalesce(each.value.kinesis_options.delivery_stream_name, "${local.resource_name_base}-${each.key}-flow-logs"), 0, 64)
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = local.kinesis_role_arns[each.key]
    bucket_arn          = local.kinesis_bucket_arns[each.key]
    buffering_interval  = each.value.kinesis_options.buffering_interval
    buffering_size      = each.value.kinesis_options.buffering_size
    compression_format  = each.value.kinesis_options.compression_format
    prefix              = each.value.kinesis_options.prefix
    error_output_prefix = each.value.kinesis_options.error_output_prefix
  }

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.vpc.name}-${each.key}-flow-logs"
  })

  depends_on = [aws_iam_role_policy.kinesis_flow_logs]
}

# ─── VPC Flow Logs ────────────────────────────────────────────────────────

resource "aws_flow_log" "this" {
  for_each = local.enabled_flow_logs

  vpc_id          = local.vpc_id
  traffic_type    = each.value.traffic_type
  log_destination = local.flow_log_destination_arns[each.key]
  log_destination_type = (
    each.value.destination_type == "cloudwatch" ? "cloud-watch-logs" :
    each.value.destination_type == "s3" ? "s3" :
    "kinesis-data-firehose"
  )
  iam_role_arn               = local.flow_log_role_arns[each.key]
  deliver_cross_account_role = each.value.deliver_cross_account_role_arn
  log_format                 = each.value.log_format
  max_aggregation_interval   = each.value.max_aggregation_interval

  dynamic "destination_options" {
    for_each = each.value.destination_type == "s3" ? [each.value.s3_options] : []

    content {
      file_format                = destination_options.value.file_format
      hive_compatible_partitions = destination_options.value.hive_compatible_partitions
      per_hour_partition         = destination_options.value.per_hour_partition
    }
  }

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.vpc.name}-${each.key}-flow-logs"
  })

  lifecycle {
    precondition {
      condition = (
        each.value.destination_type != "cloudwatch" ||
        local.flow_log_role_arns[each.key] != null
      )
      error_message = "CloudWatch flow logs require an IAM role; provide iam_role_arn or allow the module to create it."
    }
  }

  depends_on = [aws_iam_role_policy.flow_logs]
}
