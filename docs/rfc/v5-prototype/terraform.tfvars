# ─────────────────────────────────────────────────────────────────────────────
# Default fixture values for `terraform validate` — uses Example 1 (Basic)
# ─────────────────────────────────────────────────────────────────────────────

vpc = {
  name = "v5-prototype-validation"
}

addressing = {
  ipv4 = { cidr_block = "10.0.0.0/16" }
}

availability_zones = {
  count = 3
}

subnets = {
  public = {
    role = "public"
    ipv4 = { netmask = 24 }
    routing = {
      internet_gateway = true
    }
    public_options = {
      map_public_ip = true
    }
  }

  app = {
    role = "private"
    ipv4 = { netmask = 22 }
    routing = {
      nat_gateway = true
    }
  }

  database = {
    role = "isolated"
    ipv4 = { netmask = 24 }
  }
}

nat_gateway = {
  mode = "single_az"
  az   = "us-east-1a"
}
