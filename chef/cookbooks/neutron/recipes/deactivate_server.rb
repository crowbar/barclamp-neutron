unless node['roles'].include?('neutron-server')
  # HA part if node is in a cluster
  if File.exist?("/usr/sbin/crm")
    primitive_name = "neutron-server"

    pacemaker_clone "cl-#{primitive_name}" do
      action [:stop, :delete]
      only_if "crm configure show cl-#{primitive_name}"
    end

    pacemaker_primitive primitive_name do
      action [:stop, :delete]
      only_if "crm configure show #{primitive_name}"
    end
  end

  # Non HA part if service is on a standalone node
  node["neutron"]["services"]["server"].each do |name|
    service name do
      action [:stop, :disable]
    end
  end
  node['neutron']['services'].delete('server')
  node.delete('neutron') if node['neutron']['services'].empty?

  node.save
end
