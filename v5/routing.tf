# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — Route Tables + Routes (Phase 2)
#
# Design: one route table per subnet group per AZ. Key = "name/az".
# Routes are co-located: each subnet group declares its routing intent in the
# `routing` block, and resources are materialized here from that declaration.
#
# Route keys follow the pattern: "name/az/destination" for stable identity.
# ─────────────────────────────────────────────────────────────────────────────

# ─── Route Tables ──────────────────────────────────────────────────────────
# One per subnet group per AZ — enables per-AZ NAT routing without coupling.

resource "aws_route_table" "main" {
  for_each = local.route_table_map

  vpc_id = local.vpc_id

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.vpc.name}-${each.value.name_prefix}-${each.value.az}"
  })
}

# ─── Route Table Associations ──────────────────────────────────────────────
# Each subnet is associated with its group's AZ-specific route table.

resource "aws_route_table_association" "main" {
  for_each = local.subnet_map

  subnet_id      = aws_subnet.main[each.key].id
  route_table_id = aws_route_table.main[each.key].id
}

# ─── Internet Gateway Routes ──────────────────────────────────────────────

resource "aws_route" "igw_ipv4" {
  for_each = local.routes_igw

  route_table_id         = aws_route_table.main[each.value.rt_key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = local.igw_id
}

resource "aws_route" "igw_ipv6" {
  for_each = local.routes_igw_ipv6

  route_table_id              = aws_route_table.main[each.value.rt_key].id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = local.igw_id
}

# ─── NAT Gateway Routes ───────────────────────────────────────────────────

resource "aws_route" "nat" {
  for_each = local.routes_nat

  route_table_id         = aws_route_table.main[each.value.rt_key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = each.value.nat_gw_id
}

# ─── Egress-Only IGW Routes (IPv6) ────────────────────────────────────────

resource "aws_route" "eigw" {
  for_each = local.routes_eigw

  route_table_id              = aws_route_table.main[each.value.rt_key].id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = local.eigw_id
}

# ─── Transit Gateway Routes ───────────────────────────────────────────────

resource "aws_route" "tgw" {
  for_each = local.routes_tgw

  route_table_id         = aws_route_table.main[each.value.rt_key].id
  destination_cidr_block = each.value.destination
  transit_gateway_id     = each.value.tgw_id
}

resource "aws_route" "tgw_ipv6" {
  for_each = local.routes_tgw_ipv6

  route_table_id              = aws_route_table.main[each.value.rt_key].id
  destination_ipv6_cidr_block = each.value.destination
  transit_gateway_id          = each.value.tgw_id
}

# ─── Core Network Routes ──────────────────────────────────────────────────

resource "aws_route" "cwan" {
  for_each = local.routes_cwan

  route_table_id         = aws_route_table.main[each.value.rt_key].id
  destination_cidr_block = each.value.destination
  core_network_arn       = each.value.core_network_arn
}

resource "aws_route" "cwan_ipv6" {
  for_each = local.routes_cwan_ipv6

  route_table_id              = aws_route_table.main[each.value.rt_key].id
  destination_ipv6_cidr_block = each.value.destination
  core_network_arn            = each.value.core_network_arn
}
