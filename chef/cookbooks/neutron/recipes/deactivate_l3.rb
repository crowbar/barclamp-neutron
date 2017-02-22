unless node['roles'].include?('neutron-l3')
  # HA part if node is in a cluster
  if File.exist?("/usr/sbin/crm")
    agents_group_name = "g-neutron-agents"
    agents_clone_name = "cl-#{agents_group_name}"
    agents_primitives = ["neutron-l3-agent","neutron-dhcp-agent","neutron-metadata-agent","neutron-metering-agent"]
    ha_tool_primitive_name = "neutron-ha-tool"

    pacemaker_primitive ha_tool_primitive_name do
      action [:stop, :delete]
      only_if "crm configure show #{ha_tool_primitive_name}"
    end

    pacemaker_group agents_group_name do
      action :delete
      only_if "crm configure show #{agents_group_name}"
    end

    pacemaker_clone agents_clone_name do
      action [:stop, :delete]
      only_if "crm configure show #{agents_clone_name}"
    end

    agents_primitives.each do |agent|
      action [:stop,:delete]
      only_if "crm configure show #{agent}"
    end

    networking_plugin = node[:neutron][:networking_plugin]
    case networking_plugin
    when "openvswitch", "cisco"
      neutron_agent = node[:neutron][:platform][:ovs_agent_name]
    when "linuxbridge"
      neutron_agent = node[:neutron][:platform][:lb_agent_name]
    when "vmware"
      neutron_agent = node[:neutron][:platform][:nvp_agent_name]
    end
    neutron_agent.slice! 'openstack-'

    pacemaker_primitive neutron_agent do
      action [:stop, :delete]
      only_if "crm configure show #{neutron_agent}"
    end
  end

  # Non HA part if service is on a standalone node
  node["neutron"]["services"]["l3"].each do |name|
    service name do
      action [:stop, :disable]
    end
  end
  node['neutron']['services'].delete('l3')
  node.delete('neutron') if node['neutron']['services'].empty?
  node.save
end
