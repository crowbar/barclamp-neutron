name "neutron-l3_remove"
description "Remove Neutron L3 Role"
run_list(
  "recipe[neutron::remove_l3]"
)
default_attributes()
override_attributes()
