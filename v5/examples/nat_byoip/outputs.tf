output "nat_gateway_ids" {
  description = "NAT Gateway IDs for each EIP sourcing mode."
  value = {
    create     = module.create.nat_gateway_ids
    byoip_pool = module.byoip_pool.nat_gateway_ids
    existing   = module.existing.nat_gateway_ids
  }
}

output "nat_eip_allocation_ids" {
  description = "Effective EIP allocation IDs for each sourcing mode."
  value = {
    create     = module.create.nat_eip_allocation_ids
    byoip_pool = module.byoip_pool.nat_eip_allocation_ids
    existing   = module.existing.nat_eip_allocation_ids
  }
}

output "nat_public_ips" {
  description = "NAT Gateway public IPs for each sourcing mode."
  value = {
    create     = module.create.nat_public_ips
    byoip_pool = module.byoip_pool.nat_public_ips
    existing   = module.existing.nat_public_ips
  }
}
