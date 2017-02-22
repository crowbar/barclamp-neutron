case node["platform"]
when "suse"
  default["neutron"]["services"] = {
    "server" => ["openstack-neutron"],
    "l3" => ["openstack-neutron-l3-agent", "openstack-neutron-dhcp-agent", "openstack-neutron-metadata-agent", "openstack-neutron-metering-agent"]
  }
end
