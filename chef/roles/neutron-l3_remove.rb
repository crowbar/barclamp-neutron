name "neutron-l3"
description "Remove Neutron L3 Role services"

run_list(
  "recipe[neutron::deactivate_l3]"
)
