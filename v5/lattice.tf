# ─────────────────────────────────────────────────────────────────────────────
# terraform-aws-vpc v5 — VPC Lattice Service Network association (Phase 3)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_vpclattice_service_network_vpc_association" "this" {
  for_each = var.vpc_lattice == null ? {} : { vpc = var.vpc_lattice }

  vpc_identifier             = local.vpc_id
  service_network_identifier = each.value.service_network_identifier
  security_group_ids         = each.value.security_group_ids
  private_dns_enabled        = each.value.private_dns_enabled

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.vpc.name}-service-network-association"
  })

  lifecycle {
    precondition {
      condition     = length(trimspace(each.value.service_network_identifier)) > 0
      error_message = "vpc_lattice.service_network_identifier must not be empty."
    }
  }
}
