output "vpc_id" {
  description = "Injected VPC ID returned through the module's stable Tier 1 handle."
  value       = module.vpc.vpc_id
}

output "internet_gateway_id" {
  description = "Injected Internet Gateway ID returned by the module."
  value       = module.vpc.internet_gateway_id
}

output "subnet_ids" {
  description = "Module-created subnet IDs grouped by caller-owned key and AZ."
  value       = module.vpc.subnet_ids_by_group_by_az
}

output "route_table_ids" {
  description = "Effective route table IDs, including the shared injected public table."
  value       = module.vpc.route_table_ids_by_group_by_az
}

output "nat_gateway_ids" {
  description = "Module-created NAT Gateway IDs by AZ."
  value       = module.vpc.nat_gateway_ids
}

output "external_eip_allocation_ids" {
  description = "Caller-owned EIP allocation IDs passed to eip.mode=existing."
  value       = { for az, eip in aws_eip.nat : az => eip.id }
}

output "module_ownership" {
  description = "Counts proving which boundary resources the module did not create."
  value = {
    vpcs                  = length(module.vpc.resources.vpc.created)
    internet_gateways     = length(module.vpc.resources.internet_gateway)
    elastic_ips           = length(module.vpc.resources.eips)
    injected_route_tables = module.vpc.resources.injected_route_table_ids
  }
}
