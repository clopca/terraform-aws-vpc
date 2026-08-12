# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Route Tables + Routes (Phase 2)
#
# Design: create one route table per subnet group/AZ, or inject one existing
# shared table for a group. Routes are co-located: each subnet group declares
# its routing intent and resources are materialized here from that declaration.
#
# Route keys follow the pattern: "name/az/destination" for stable identity.
# ─────────────────────────────────────────────────────────────────────────────

# ─── Route Tables ──────────────────────────────────────────────────────────
# One per subnet group per AZ — enables per-AZ NAT routing without coupling.

resource "aws_route_table" "main" {
  for_each = local.route_table_map

  vpc_id = local.vpc_id

  tags = merge(var.tags, each.value.tags, {
    Name = each.value.route_table_name
  })
}

# ─── Route Table Associations ──────────────────────────────────────────────
# Each subnet is associated with its group's AZ-specific route table.

resource "aws_route_table_association" "main" {
  for_each = local.subnet_map

  subnet_id      = local.subnet_ids[each.key]
  route_table_id = local.route_table_id_by_subnet[each.key]
}

# ─── Internet Gateway Routes ──────────────────────────────────────────────

resource "aws_route" "igw_ipv4" {
  for_each = local.routes_igw

  route_table_id         = each.value.route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = local.igw_id
}

resource "aws_route" "igw_ipv6" {
  for_each = local.routes_igw_ipv6

  route_table_id              = each.value.route_table_id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = local.igw_id
}

# ─── NAT Gateway Routes ───────────────────────────────────────────────────

resource "aws_route" "nat" {
  for_each = local.routes_nat

  route_table_id         = each.value.route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = each.value.nat_gw_id
}

# DNS64 requires this more-specific NAT64 route in addition to enable_dns64.
resource "aws_route" "nat64" {
  for_each = local.routes_nat64

  route_table_id              = each.value.route_table_id
  destination_ipv6_cidr_block = "64:ff9b::/96"
  nat_gateway_id              = each.value.nat_gw_id
}

# ─── Egress-Only IGW Routes (IPv6) ────────────────────────────────────────

resource "aws_route" "eigw" {
  for_each = local.routes_eigw

  route_table_id              = each.value.route_table_id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = local.eigw_id
}

# ─── Transit Gateway Routes ───────────────────────────────────────────────

resource "aws_route" "tgw" {
  for_each = local.routes_tgw

  route_table_id             = each.value.route_table_id
  destination_cidr_block     = startswith(each.value.destination, "pl-") ? null : each.value.destination
  destination_prefix_list_id = startswith(each.value.destination, "pl-") ? each.value.destination : null
  transit_gateway_id         = each.value.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_route" "tgw_ipv6" {
  for_each = local.routes_tgw_ipv6

  route_table_id              = each.value.route_table_id
  destination_ipv6_cidr_block = startswith(each.value.destination, "pl-") ? null : each.value.destination
  destination_prefix_list_id  = startswith(each.value.destination, "pl-") ? each.value.destination : null
  transit_gateway_id          = each.value.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

# ─── Core Network Routes ──────────────────────────────────────────────────

resource "aws_route" "cwan" {
  for_each = local.routes_cwan

  route_table_id             = each.value.route_table_id
  destination_cidr_block     = startswith(each.value.destination, "pl-") ? null : each.value.destination
  destination_prefix_list_id = startswith(each.value.destination, "pl-") ? each.value.destination : null
  core_network_arn           = each.value.core_network_arn

  depends_on = [
    aws_networkmanager_vpc_attachment.this,
    aws_networkmanager_attachment_accepter.this,
  ]
}

resource "aws_route" "cwan_ipv6" {
  for_each = local.routes_cwan_ipv6

  route_table_id              = each.value.route_table_id
  destination_ipv6_cidr_block = startswith(each.value.destination, "pl-") ? null : each.value.destination
  destination_prefix_list_id  = startswith(each.value.destination, "pl-") ? each.value.destination : null
  core_network_arn            = each.value.core_network_arn

  depends_on = [
    aws_networkmanager_vpc_attachment.this,
    aws_networkmanager_attachment_accepter.this,
  ]
}
