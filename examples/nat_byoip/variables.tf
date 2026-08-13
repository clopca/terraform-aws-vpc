variable "public_ipv4_pool" {
  description = "EC2 public IPv4 address pool ID for BYOIP (e.g. ipv4pool-ec2-xxxxxxxxxxxxxxxxx)."
  type        = string
  default     = "ipv4pool-ec2-0123456789abcdef0"
}

variable "existing_eip_allocation_ids" {
  description = "Map of AZ to pre-existing EIP allocation ID."
  type        = map(string)
  default = {
    "us-east-1a" = "eipalloc-0123456789abcdef0"
    "us-east-1b" = "eipalloc-0123456789abcdef1"
  }
}
