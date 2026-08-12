output "vpc_id" {
  description = "VPC ID of the primary VPC."
  value       = module.vpc.vpc_attributes.id
}

output "secondary_cidr_block" {
  description = "The secondary CIDR block allocated by IPAM."
  value       = module.vpc_secondary_cidr_ipam.vpc_attributes.id
}
