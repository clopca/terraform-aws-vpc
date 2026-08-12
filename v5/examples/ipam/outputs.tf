output "vpc_id" {
  description = "ID of the IPAM-addressed VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "Primary IPv4 CIDR allocated by IPAM."
  value       = module.vpc.vpc_cidr_block
}

output "vpc_ipv6_cidr_block" {
  description = "IPv6 CIDR allocated by IPAM."
  value       = module.vpc.vpc_ipv6_cidr_block
}

output "secondary_cidr_association_ids" {
  description = "Static and IPAM secondary association IDs by stable caller key."
  value       = module.vpc.secondary_cidr_association_ids
}

output "subnet_ids" {
  description = "Subnet IDs by group and Availability Zone."
  value       = module.vpc.subnet_ids_by_group_by_az
}

output "subnet_ipv6_cidrs" {
  description = "IPv6 subnet CIDRs; values allocated by subnet IPAM become known after apply."
  value       = module.vpc.subnet_ipv6_cidrs_by_group_by_az
}
