# terraform-aws-vpc v5 — opt-in adoption of AWS-created default resources
#
# AWS creates these resources with every VPC. The provider resources adopt them
# by ID and reconcile their mutable rules/routes; they do not create replacements.

data "aws_network_acls" "default" {
  for_each = var.default_resources.manage_network_acl ? { default = true } : {}

  vpc_id = local.vpc_id

  filter {
    name   = "default"
    values = ["true"]
  }
}

data "aws_route_table" "default" {
  for_each = var.default_resources.manage_route_table ? { default = true } : {}

  vpc_id = local.vpc_id

  filter {
    name   = "association.main"
    values = ["true"]
  }
}

locals {
  default_resource_names = {
    security_group = replace(replace(var.default_resources.name_format, "{vpc}", var.vpc.name), "{resource}", "default-security-group")
    network_acl    = replace(replace(var.default_resources.name_format, "{vpc}", var.vpc.name), "{resource}", "default-network-acl")
    route_table    = replace(replace(var.default_resources.name_format, "{vpc}", var.vpc.name), "{resource}", "default-route-table")
  }
}

resource "aws_default_security_group" "this" {
  for_each = var.default_resources.manage_security_group ? { default = true } : {}

  vpc_id  = local.vpc_id
  ingress = []
  egress  = []

  tags = merge(var.tags, var.default_resources.tags, {
    Name = local.default_resource_names.security_group
  })
}

resource "aws_default_network_acl" "this" {
  for_each = var.default_resources.manage_network_acl ? { default = true } : {}

  default_network_acl_id = one(data.aws_network_acls.default[each.key].ids)

  tags = merge(var.tags, var.default_resources.tags, {
    Name = local.default_resource_names.network_acl
  })
}

resource "aws_default_route_table" "this" {
  for_each = var.default_resources.manage_route_table ? { default = true } : {}

  default_route_table_id = data.aws_route_table.default[each.key].id
  propagating_vgws       = []
  route                  = []

  tags = merge(var.tags, var.default_resources.tags, {
    Name = local.default_resource_names.route_table
  })
}
