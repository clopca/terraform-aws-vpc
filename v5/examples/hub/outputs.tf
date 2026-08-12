output "vpc_id" {
  description = "ID of the network hub VPC."
  value       = module.vpc.vpc_id
}

output "subnet_ids" {
  description = "Hub subnet IDs by group and Availability Zone."
  value       = module.vpc.subnet_ids_by_group_by_az
}

output "subnet_ipv6_cidrs" {
  description = "Hub IPv6 CIDRs by group and Availability Zone."
  value       = module.vpc.subnet_ipv6_cidrs_by_group_by_az
}

output "subnets_by_role" {
  description = "Hub subnet IDs grouped by semantic role."
  value       = module.vpc.subnet_ids_by_semantic_role
}

output "igw_id" {
  description = "Injected Internet Gateway ID used by the hub VPC."
  value       = module.vpc.internet_gateway_id
}

output "nat_gateway_ids" {
  description = "Public hub NAT Gateway IDs by Availability Zone."
  value       = module.vpc.nat_gateway_ids
}

output "nat_public_ips" {
  description = "Public hub NAT Gateway IPs by Availability Zone."
  value       = module.vpc.nat_public_ips
}

output "route_tables" {
  description = "Hub route table IDs by subnet group and Availability Zone."
  value       = module.vpc.route_table_ids_by_group_by_az
}

output "route_tables_by_role" {
  description = "Hub route table IDs grouped by semantic role."
  value       = module.vpc.route_table_ids_by_semantic_role
}

output "inspection_vpc_id" {
  description = "ID of the private-NAT inspection VPC."
  value       = module.inspection_vpc.vpc_id
}

output "inspection_nat_ids" {
  description = "Private inspection NAT Gateway IDs by Availability Zone."
  value       = module.inspection_vpc.nat_gateway_ids
}

output "transit_gateway_attachment_id" {
  description = "ID of the hub Transit Gateway attachment."
  value       = module.vpc.transit_gateway_attachment_id
}

output "core_network_attachment_id" {
  description = "ID of the hub Cloud WAN Core Network attachment."
  value       = module.vpc.core_network_attachment_id
}

output "flow_log_ids" {
  description = "Hub VPC Flow Log IDs by stable flow-log key."
  value       = module.vpc.flow_log_ids
}
