# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — NAT Gateways + EIPs (Phase 2)
#
# Create-or-inject pattern:
#   - nat_gateway.existing_ids set → use existing NAT GWs (no EIP/NAT creation)
#   - nat_gateway.existing_ids null → create NAT GWs + EIPs per mode
#
# EIP sourcing: create (new) | byoip_pool (BYO pool) | existing (allocation_ids)
# Connectivity type: public (default) | private (no EIP needed)
#
# for_each keys: "nat/<az>" — stable, deterministic.
# ─────────────────────────────────────────────────────────────────────────────

# ─── Elastic IPs for NAT Gateways ─────────────────────────────────────────
# Created only when:
#   - mode != "none"
#   - existing_ids not set (create mode for NAT)
#   - connectivity_type = "public" (private NAT doesn't need EIPs)
#   - eip.mode != "existing" (user provides allocation_ids)

resource "aws_eip" "nat" {
  for_each = local.nat_eips_to_create

  domain           = "vpc"
  public_ipv4_pool = var.nat_gateway.eip.public_ipv4_pool

  tags = merge(var.tags, each.value.tags, {
    Name = each.value.name
  })
}

# ─── NAT Gateways ─────────────────────────────────────────────────────────
# Created only when existing_ids is not set (create mode).
# Placed in nat_gateway.subnet_group, or the documented first compatible
# group fallback when subnet_group is null.

resource "aws_nat_gateway" "main" {
  for_each = local.nat_gateways_to_create

  allocation_id     = each.value.connectivity_type == "public" ? each.value.allocation_id : null
  connectivity_type = each.value.connectivity_type
  subnet_id         = each.value.subnet_id

  tags = merge(var.tags, each.value.tags, {
    Name = each.value.name
  })

  depends_on = [aws_internet_gateway.main]
}

# ─── Egress-Only Internet Gateway (IPv6) ──────────────────────────────────
# Created when any subnet has routing.egress_only_igw = true.

resource "aws_egress_only_internet_gateway" "main" {
  count = local.create_eigw ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(var.tags, var.vpc.eigw_tags, {
    Name = replace(var.vpc.eigw_name_format, "{vpc}", var.vpc.name)
  })
}
