variable "aws_region" {
  description = "AWS Region containing the injected hub dependencies."
  type        = string
  default     = "us-west-2"
}

variable "existing_igw_id" {
  description = "Existing Internet Gateway ID attached to the hub VPC."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^igw-[0-9a-f]{8,17}$", var.existing_igw_id))
    error_message = "existing_igw_id must be a valid Internet Gateway ID."
  }
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID used by the hub and inspection VPC attachments."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^tgw-[0-9a-f]{8,17}$", var.transit_gateway_id))
    error_message = "transit_gateway_id must be a valid Transit Gateway ID."
  }
}

variable "core_network_id" {
  description = "Cloud WAN Core Network ID used by the hub attachment."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^cnet-[0-9a-f]{8,17}$", var.core_network_id))
    error_message = "core_network_id must be a valid Core Network ID."
  }
}

variable "core_network_arn" {
  description = "Cloud WAN Core Network ARN matching core_network_id."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:(aws|aws-us-gov|aws-cn):networkmanager::[0-9]{12}:core-network/cnet-[0-9a-f]{8,17}$", var.core_network_arn))
    error_message = "core_network_arn must be a valid Cloud WAN Core Network ARN."
  }
}

variable "nat_eip_allocation_ids" {
  description = "Existing EIP allocation IDs for the three hub NAT Gateways, keyed by AZ."
  type        = map(string)
  nullable    = false

  validation {
    condition = (
      toset(keys(var.nat_eip_allocation_ids)) == toset(["us-west-2a", "us-west-2b", "us-west-2c"]) &&
      alltrue([for id in values(var.nat_eip_allocation_ids) : can(regex("^eipalloc-[0-9a-f]{8,17}$", id))])
    )
    error_message = "nat_eip_allocation_ids must contain valid EIP allocation IDs for us-west-2a, us-west-2b, and us-west-2c."
  }
}

variable "flow_log_destination_arn" {
  description = "Existing Kinesis Data Firehose delivery stream ARN for VPC Flow Logs."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:(aws|aws-us-gov|aws-cn):firehose:[a-z0-9-]+:[0-9]{12}:deliverystream/.+$", var.flow_log_destination_arn))
    error_message = "flow_log_destination_arn must be a valid Kinesis Data Firehose delivery stream ARN."
  }
}
