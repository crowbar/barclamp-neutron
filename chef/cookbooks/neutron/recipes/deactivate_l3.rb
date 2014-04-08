unless node['roles'].include?('neutron-l3')
  node["neutron"]["services"]["l3"].each do |name|
    service name do
      action [:stop, :disable]
    end
  end
  node['neutron']['services'].delete('l3')
  node.delete('neutron') if node['neutron']['services'].empty?
  node.save
end
