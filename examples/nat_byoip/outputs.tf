output "byoip_pool_nat_gateway_ids" {
  description = "Map of AZ to NAT Gateway ID for the BYOIP pool example."
  value       = module.vpc_byoip_pool.nat_gateway_ids
}

output "byoip_pool_nat_public_ips" {
  description = "Map of AZ to NAT Gateway public IP for the BYOIP pool example."
  value       = module.vpc_byoip_pool.nat_public_ips
}

output "existing_eip_nat_gateway_ids" {
  description = "Map of AZ to NAT Gateway ID for the existing-EIPs example."
  value       = module.vpc_existing_eips.nat_gateway_ids
}

output "existing_eip_nat_public_ips" {
  description = "Map of AZ to NAT Gateway public IP for the existing-EIPs example."
  value       = module.vpc_existing_eips.nat_public_ips
}
