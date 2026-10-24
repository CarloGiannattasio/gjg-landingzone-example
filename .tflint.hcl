config {
  # Lint local module calls from root/ into modules/. Registry modules are not used.
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
