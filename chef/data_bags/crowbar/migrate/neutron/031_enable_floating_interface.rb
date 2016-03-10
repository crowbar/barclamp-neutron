def upgrade(ta, td, a, d)
  # This migration does not update anything on the proposals/roles but
  # it tries to enable the nova_floating network on all nodes that need
  # it.
  nodes = NodeObject.find("roles:neutron-network OR roles:neutron-l3")
  # When using DVR we need to update the compute nodes as well
  if nodes.first["neutron"]["use_dvr"]
    nodes << NodeObject.find("roles:nova-multi-compute-* NOT roles:nova-multi-compute-vmware")
    nodes.flatten!
  end
  net_svc = NetworkService.new Rails.logger
  nodes.each do |n|
    net_svc.enable_interface "default", "nova_floating", n.name
  end
  return a, d
end
