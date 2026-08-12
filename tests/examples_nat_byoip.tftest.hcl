run "validate_byoip" {
  command = plan
  module {
    source = "./examples/nat_byoip"
  }
}
