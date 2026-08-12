run "validate" {
  command = plan
  module {
    source = "./examples/ipam_secondary_cidr"
  }
}
