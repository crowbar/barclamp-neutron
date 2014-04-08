unless node['roles'].include?('neutron-server')
  node["neutron"]["services"]["server"].each do |name|
    service name do
      action [:stop, :disable]
    end
  end
  node['neutron']['services'].delete('server')
  node.delete('neutron') if node['neutron']['services'].empty?
  node.save
end
