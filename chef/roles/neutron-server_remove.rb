name "neutron-server"
description "Remove Neutron server Role services"

run_list(
  "recipe[neutron::deactivate_server]"
)
