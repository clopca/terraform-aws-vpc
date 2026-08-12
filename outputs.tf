output "vpc_attributes" {
  description = "VPC resource attributes. Full output of aws_vpc."
  value       = local.vpc
}

output "azs" {
  description = "List of AZs where subnets are created."
  value       = local.azs
}

output "transit_gateway_attachment_id" {
  description = "Transit gateway attachment id."
  value       = try(aws_ec2_transit_gateway_vpc_attachment.tgw[0].id, null)
}

output "core_network_attachment" {
  description = "AWS Cloud WAN's core network attachment. Full output of aws_networkmanager_vpc_attachment."
  value       = try(aws_networkmanager_vpc_attachment.cwan[0], null)
}

output "private_subnet_attributes_by_az" {
  value       = try(aws_subnet.private, null)
  description = <<-EOF
  Map of all private subnets containing their attributes.

  Example:
  ```
  private_subnet_attributes_by_az = {
    "private/us-east-1a" = {
      "arn" = "arn:aws:ec2:us-east-1:<>:subnet/subnet-04a86315c4839b519"
      "assign_ipv6_address_on_creation" = false
      ...
      <all attributes of subnet: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet#attributes-reference>
    }
    "us-east-1b" = {...)
  }
  ```
EOF
}

output "public_subnet_attributes_by_az" {
  value       = try(aws_subnet.public, null)
  description = <<-EOF
  Map of all public subnets containing their attributes.

  Example:
  ```
  public_subnet_attributes_by_az = {
    "us-east-1a" = {
      "arn" = "arn:aws:ec2:us-east-1:<>:subnet/subnet-04a86315c4839b519"
      "assign_ipv6_address_on_creation" = false
      ...
      <all attributes of subnet: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet#attributes-reference>
    }
    "us-east-1b" = {...)
  }
  ```
EOF
}

output "tgw_subnet_attributes_by_az" {
  value       = try(aws_subnet.tgw, null)
  description = <<-EOF
  Map of all tgw subnets containing their attributes.

  Example:
  ```
  tgw_subnet_attributes_by_az = {
    "us-east-1a" = {
      "arn" = "arn:aws:ec2:us-east-1:<>:subnet/subnet-04a86315c4839b519"
      "assign_ipv6_address_on_creation" = false
      ...
      <all attributes of subnet: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet#attributes-reference>
    }
    "us-east-1b" = {...)
  }
  ```
EOF
}

output "core_network_subnet_attributes_by_az" {
  value       = try(aws_subnet.cwan, null)
  description = <<-EOF
  Map of all core_network subnets containing their attributes.

  Example:
  ```
  core_network_subnet_attributes_by_az = {
    "us-east-1a" = {
      "arn" = "arn:aws:ec2:us-east-1:<>:subnet/subnet-04a86315c4839b519"
      "assign_ipv6_address_on_creation" = false
      ...
      <all attributes of subnet: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet#attributes-reference>
    }
    "us-east-1b" = {...)
  }
  ```
EOF
}

output "rt_attributes_by_type_by_az" {
  value = {
    # TODO: omit keys if value is null
    "private"         = aws_route_table.private,
    "public"          = aws_route_table.public
    "transit_gateway" = aws_route_table.tgw
    "core_network"    = aws_route_table.cwan
  }
  description = <<-EOF
  Map of route tables by type => az => route table attributes. Example usage: module.vpc.rt_attributes_by_type_by_az.private.id

  Example:
  ```
  rt_attributes_by_type_by_az = {
    "private" = {
      "us-east-1a" = {
        "id" = "rtb-0e77040c0598df003"
        "tags" = tolist([
          {
            "key" = "Name"
            "value" = "private-us-east-1a"
          },
        ])
        "vpc_id" = "vpc-033e054f49409592a"
        ...
        <all attributes of route: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table#attributes-reference>
      }
      "us-east-1b" = { ... }
    "public" = { ... }
  ```
EOF
}

output "nat_gateway_attributes_by_az" {
  value       = try(aws_nat_gateway.main, null)
  description = <<-EOF
  Map of nat gateway resource attributes by AZ.

  Example:
  ```
  nat_gateway_attributes_by_az = {
    "us-east-1a" = {
      "allocation_id" = "eipalloc-0e8b20303eea88b13"
      "connectivity_type" = "public"
      "id" = "nat-0fde39f9550f4abb5"
      "network_interface_id" = "eni-0d422727088bf9a86"
      "private_ip" = "10.0.3.40"
      "public_ip" = <>
      "subnet_id" = "subnet-0f11c92e439c8ab4a"
      "tags" = tomap({
        "Name" = "nat-my-public-us-east-1a"
      })
      "tags_all" = tomap({
        "Name" = "nat-my-public-us-east-1a"
      })
    }
    "us-east-1b" = { ... }
  }
  ```
EOF
}

output "natgw_id_per_az" {
  value       = try(local.nat_per_az, null)
  description = <<-EOF
  Map of nat gateway IDs for each resource. Will be duplicate ids if your var.subnets.public.nat_gateway_configuration = "single_az".

  Example:
  ```
  natgw_id_per_az = {
    "us-east-1a" = {
      "id" = "nat-0fde39f9550f4abb5"
    }
    "us-east-1b" = {
      "id" = "nat-0fde39f9550f4abb5"
     }
  }
  ```
EOF
}

output "internet_gateway" {
  value       = try(aws_internet_gateway.main[0], null)
  description = "Internet gateway attributes. Full output of aws_internet_gateway."
}

output "egress_only_internet_gateway" {
  value       = try(aws_egress_only_internet_gateway.eigw[0], null)
  description = "Egress-only Internet gateway attributes. Full output of aws_egress_only_internet_gateway."
}

output "vpc_lattice_service_network_association" {
  value       = try(aws_vpclattice_service_network_vpc_association.vpc_lattice_service_network_association[0], null)
  description = "VPC Lattice Service Network VPC association. Full output of aws_vpclattice_service_network_vpc_association"
}

output "flow_log_attributes" {
  description = "Flow Log information."
  value       = try(module.flow_logs[0].flow_log, null)
}

# ---------- ROLE-BASED CONVENIENCE OUTPUTS (v4.6+) ----------
# These outputs address the confusion reported in #177 and #159:
# private_subnet_attributes_by_az includes BOTH NAT-routed and isolated subnets,
# causing users to accidentally deploy compute into non-routable networks.

output "subnet_ids_by_role" {
  description = <<-EOF
  Map of subnet role to map of AZ to subnet ID. Distinguishes NAT-connected
  private subnets from isolated ones. Fixes #177, #159.

  Example:
  ```
  subnet_ids_by_role = {
    "private" = {
      "us-east-1a" = "subnet-0a1b2c3d"
      "us-east-1b" = "subnet-0e4f5a6b"
    }
    "isolated" = {
      "us-east-1a" = "subnet-0c7d8e9f"
      "us-east-1b" = "subnet-0a1b2c3d"
    }
    "public" = {
      "us-east-1a" = "subnet-0f1a2b3c"
    }
    "transit_gateway" = {
      "us-east-1a" = "subnet-0d4e5f6a"
    }
  }
  ```
  EOF
  value = merge(
    # Public subnets
    try(length(aws_subnet.public) > 0, false) ? {
      "public" = { for az, subnet in aws_subnet.public : az => subnet.id }
    } : {},
    # Transit gateway subnets
    try(length(aws_subnet.tgw) > 0, false) ? {
      "transit_gateway" = { for az, subnet in aws_subnet.tgw : az => subnet.id }
    } : {},
    # Core network subnets
    try(length(aws_subnet.cwan) > 0, false) ? {
      "core_network" = { for az, subnet in aws_subnet.cwan : az => subnet.id }
    } : {},
    # Private subnets split by NAT connectivity
    {
      for role in local.private_subnet_names : role => {
        for az in local.azs : az => aws_subnet.private["${role}/${az}"].id
      }
    }
  )
}

output "natgw_subnet_ids" {
  description = <<-EOF
  Flat list of private subnet IDs that have a route to a NAT gateway
  (connect_to_public_natgw = true). Use this to safely place compute workloads
  that require outbound Internet access. Fixes #177.

  Example:
  ```
  natgw_subnet_ids = ["subnet-0a1b2c3d", "subnet-0e4f5a6b", "subnet-0c7d8e9f"]
  ```
  EOF
  value = [
    for key in try(local.private_subnet_names_nat_routed, []) :
    aws_subnet.private[key].id
  ]
}

output "isolated_subnet_ids" {
  description = <<-EOF
  Flat list of private subnet IDs that do NOT have a route to a NAT gateway
  (no outbound Internet connectivity). Use this for databases, internal services,
  or workloads that must not reach the Internet. Fixes #177.

  Example:
  ```
  isolated_subnet_ids = ["subnet-0d4e5f6a", "subnet-0b7c8d9e"]
  ```
  EOF
  value = [
    for key in try(local.private_per_az, []) :
    aws_subnet.private[key].id
    if !contains(local.private_subnets_nat_routed, split("/", key)[0])
  ]
}

output "route_table_ids_by_type_by_az" {
  description = <<-EOF
  Map of route table type to map of AZ to route table ID. Provides simple ID
  access without needing to extract .id from the full resource objects in
  rt_attributes_by_type_by_az.

  Example:
  ```
  route_table_ids_by_type_by_az = {
    "private" = {
      "private/us-east-1a" = "rtb-0a1b2c3d"
      "private/us-east-1b" = "rtb-0e4f5a6b"
    }
    "public" = {
      "us-east-1a" = "rtb-0c7d8e9f"
    }
    "transit_gateway" = {
      "us-east-1a" = "rtb-0d4e5f6a"
    }
    "core_network" = {}
  }
  ```
  EOF
  value = {
    "private"         = { for k, v in aws_route_table.private : k => v.id }
    "public"          = { for k, v in aws_route_table.public : k => v.id }
    "transit_gateway" = { for k, v in aws_route_table.tgw : k => v.id }
    "core_network"    = { for k, v in aws_route_table.cwan : k => v.id }
  }
}
