# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Transit Gateway and Cloud WAN attachments (Phase 3)
#
# Attachment resources use a constant singleton key ("vpc"), not a subnet-group
# position. Inputs reference only scalar IDs/ARNs and child resource attributes;
# no complete data-source object can become unknown and force replacement.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  transit_gateway_group = try([
    for name, cfg in var.subnets : name if cfg.role == "transit_gateway"
  ][0], null)

  core_network_group = try([
    for name, cfg in var.subnets : name if cfg.role == "core_network"
  ][0], null)

  transit_gateway_attachment = local.transit_gateway_group == null ? {} : {
    vpc = {
      group   = local.transit_gateway_group
      options = var.subnets[local.transit_gateway_group].transit_gateway_options
      tags    = var.subnets[local.transit_gateway_group].tags
      ipv6 = try(
        var.subnets[local.transit_gateway_group].ipv6 != null,
        false
      )
    }
  }

  core_network_attachment = local.core_network_group == null ? {} : {
    vpc = {
      group   = local.core_network_group
      options = var.subnets[local.core_network_group].core_network_options
      tags    = var.subnets[local.core_network_group].tags
      ipv6 = try(
        var.subnets[local.core_network_group].ipv6 != null,
        false
      )
    }
  }

  # Construct the immutable VPC ARN from scalar identity components. In inject
  # mode this avoids data.aws_vpc.existing[0].arn and its whole-object unknowns.
  constructed_vpc_arn = local.core_network_group == null ? null : format(
    "arn:%s:ec2:%s:%s:vpc/%s",
    data.aws_partition.current[0].partition,
    data.aws_region.current[0].name,
    data.aws_caller_identity.current[0].account_id,
    local.vpc_id
  )

  any_transit_gateway_routes = anytrue([
    for name, cfg in var.subnets :
    length(coalesce(try(cfg.routing.transit_gateway, null), [])) > 0 ||
    length(coalesce(try(cfg.routing.transit_gateway_ipv6, null), [])) > 0
  ])

  any_core_network_routes = anytrue([
    for name, cfg in var.subnets :
    length(coalesce(try(cfg.routing.core_network, null), [])) > 0 ||
    length(coalesce(try(cfg.routing.core_network_ipv6, null), [])) > 0
  ])
}

data "aws_partition" "current" {
  count = local.core_network_group == null ? 0 : 1
}

data "aws_region" "current" {
  count = local.core_network_group == null ? 0 : 1
}

resource "terraform_data" "attachment_contract_validation" {
  input = {
    transit_gateway_group = local.transit_gateway_group
    core_network_group    = local.core_network_group
  }

  lifecycle {
    precondition {
      condition     = !local.any_transit_gateway_routes || local.transit_gateway_group != null
      error_message = "A subnet group declares Transit Gateway routes, but no subnet group has role = 'transit_gateway'. Add the attachment group or remove those routes."
    }

    precondition {
      condition     = !local.any_core_network_routes || local.core_network_group != null
      error_message = "A subnet group declares Cloud WAN routes, but no subnet group has role = 'core_network'. Add the attachment group or remove those routes."
    }

    precondition {
      condition = local.core_network_group == null ? true : (
        try(var.subnets[local.core_network_group].core_network_options.arn, null) == null ||
        endswith(
          var.subnets[local.core_network_group].core_network_options.arn,
          "/${var.subnets[local.core_network_group].core_network_options.id}"
        )
      )
      error_message = "core_network_options.arn must identify the same Core Network as core_network_options.id."
    }
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = local.transit_gateway_attachment

  transit_gateway_id = each.value.options.id
  vpc_id             = local.vpc_id
  subnet_ids = [
    for az in local.azs : aws_subnet.main["${each.value.group}/${az}"].id
  ]

  transit_gateway_default_route_table_association = each.value.options.default_route_table_association
  transit_gateway_default_route_table_propagation = each.value.options.default_route_table_propagation
  appliance_mode_support                          = each.value.options.appliance_mode_support ? "enable" : "disable"
  dns_support                                     = each.value.options.dns_support ? "enable" : "disable"
  ipv6_support                                    = each.value.ipv6 ? "enable" : "disable"
  security_group_referencing_support              = each.value.options.security_group_referencing ? "enable" : "disable"

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.vpc.name}-tgw-attachment"
  })

  lifecycle {
    precondition {
      condition     = length(trimspace(each.value.options.id)) > 0
      error_message = "transit_gateway_options.id must not be empty."
    }
  }
}

resource "aws_networkmanager_vpc_attachment" "this" {
  for_each = local.core_network_attachment

  core_network_id = each.value.options.id
  vpc_arn         = local.constructed_vpc_arn
  subnet_arns = [
    for az in local.azs : aws_subnet.main["${each.value.group}/${az}"].arn
  ]

  options {
    appliance_mode_support = each.value.options.appliance_mode
    ipv6_support           = each.value.ipv6
  }

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.vpc.name}-core-network-attachment"
  })

  lifecycle {
    # The VPC ARN is immutable. Ignoring this ForceNew argument prevents the v4
    # issue where unrelated existing-VPC changes propagated an unknown ARN and
    # destructively replaced the Cloud WAN attachment.
    ignore_changes = [vpc_arn]

    precondition {
      condition     = length(trimspace(each.value.options.id)) > 0
      error_message = "core_network_options.id must not be empty."
    }
  }
}

resource "aws_networkmanager_attachment_accepter" "this" {
  for_each = {
    for key, attachment in local.core_network_attachment : key => attachment
    if attachment.options.require_acceptance && attachment.options.accept_attachment
  }

  attachment_id   = aws_networkmanager_vpc_attachment.this[each.key].id
  attachment_type = "VPC"
}
