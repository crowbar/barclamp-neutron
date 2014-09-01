resource = "neutron"
main_role = "l3"
role_name = "#{resource}-#{main_role}"

unless node["roles"].include?(role_name)
  neutron_l3_service = []
  neutron_l3_service << node[resource]["platform"]["ha_tool_pkg"]
  ["l3_agent","dhcp_agent","metadata_agent","metering_agent"].each do |name| # lbaas-agent
    neutron_l3_service << node[resource]["platform"]["#{name}_name"]
  end

  networking_plugin = node[:neutron][:networking_plugin]
  case networking_plugin
  when "openvswitch", "cisco"
    neutron_agent = node[:neutron][:platform][:ovs_agent_name]
    #neutron_l3_service << "openstack-neutron-ovs-cleanup" << "openstack-neutron-openvswitch-agent" << openvswitch-switch" if node["platform"] == "suse"
  when "linuxbridge"
    neutron_agent = node[:neutron][:platform][:lb_agent_name]
  when "vmware"
    neutron_agent = node[:neutron][:platform][:nvp_agent_name]
  end
  neutron_l3_service << neutron_agent

  barclamp_role role_name do
    service_name neutron_l3_service
    action :remove
  end

  # delete all attributes from node
  node.delete(resource) unless node["roles"].include?("#{resource}-server_remove")

  node.save
end
