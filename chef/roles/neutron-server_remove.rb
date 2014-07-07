name "neutron-server_remove"
description "Remove Neutron server Role services"

run_list(
  "recipe[neutron::deactivate_server]"
)
