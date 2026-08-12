output "vpc_id" {
  description = "ID of the enterprise VPC."
  value       = module.vpc.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs by group and Availability Zone."
  value       = module.vpc.subnet_ids_by_group_by_az
}

output "subnet_cidrs" {
  description = "IPv4 CIDRs by group and Availability Zone."
  value       = module.vpc.subnet_cidrs_by_group_by_az
}

output "subnet_ipv6_cidrs" {
  description = "IPv6 CIDRs by group and Availability Zone."
  value       = module.vpc.subnet_ipv6_cidrs_by_group_by_az
}

output "subnets_by_role" {
  description = "Subnet IDs grouped by semantic role."
  value       = module.vpc.subnet_ids_by_semantic_role
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs by Availability Zone."
  value       = module.vpc.nat_gateway_ids
}

output "nat_public_ips" {
  description = "NAT Gateway public IPs by Availability Zone."
  value       = module.vpc.nat_public_ips
}

output "route_tables" {
  description = "Route table IDs by subnet group and Availability Zone."
  value       = module.vpc.route_table_ids_by_group_by_az
}

output "eigw_id" {
  description = "ID of the egress-only Internet Gateway."
  value       = module.vpc.egress_only_igw_id
}

output "flow_log_ids" {
  description = "VPC Flow Log IDs by stable flow-log key."
  value       = module.vpc.flow_log_ids
}

output "lattice_association_id" {
  description = "ID of the VPC Lattice service-network association."
  value       = module.vpc.vpc_lattice_service_network_association_id
}
