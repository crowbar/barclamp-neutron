resource = "neutron"
main_role = "server"
role_name = "#{resource}-#{main_role}"

unless node["roles"].include?(role_name)
  neutron_server_service = node[resource]["platform"]["service_name"]
  neutron_server_service.slice! "openstack-"
  neutron_server_service << "-server"

  barclamp_role role_name do
    service_name neutron_server_service
    action :remove
  end

  # delete all attributes from node
  node.delete(resource) unless node["roles"].include?("#{resource}-l3_remove")

  node.save
end
