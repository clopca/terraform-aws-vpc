output "byoip_pool_nat_gateway_ids" {
  value = module.vpc_byoip_pool.nat_gateway_ids
}

output "byoip_pool_nat_public_ips" {
  value = module.vpc_byoip_pool.nat_public_ips
}

output "existing_eip_nat_gateway_ids" {
  value = module.vpc_existing_eips.nat_gateway_ids
}

output "existing_eip_nat_public_ips" {
  value = module.vpc_existing_eips.nat_public_ips
}
