name "neutron-server_remove"
description "Remove Neutron server Role"
run_list(
  "recipe[neutron::remove_server]"
)
default_attributes()
override_attributes()
