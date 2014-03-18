# Copyright 2011 Dell, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

unless node[:neutron][:use_gitrepo]
  pkgs = node[:neutron][:platform][:pkgs]
  pkgs.each { |p| package p }
else
  neutron_path = "/opt/neutron"
  venv_path = node[:neutron][:use_virtualenv] ? "#{neutron_path}/.venv" : nil

  link_service "neutron-server" do
    virtualenv venv_path
    bin_name "neutron-server --config-dir /etc/neutron/"
  end
end


include_recipe "neutron::database"
include_recipe "neutron::common_config"


env_filter = " AND keystone_config_environment:keystone-config-#{node[:neutron][:keystone_instance]}"
keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
if keystones.length > 0
  keystone = keystones[0]
  keystone = node if keystone.name == node.name
else
  keystone = node
end

keystone_host = keystone[:fqdn]
keystone_protocol = keystone["keystone"]["api"]["protocol"]
keystone_service_port = keystone["keystone"]["api"]["service_port"]
keystone_admin_port = keystone["keystone"]["api"]["admin_port"]
keystone_service_tenant = keystone["keystone"]["service"]["tenant"]
keystone_service_user = node["neutron"]["service_user"]
keystone_service_password = node["neutron"]["service_password"]
Chef::Log.info("Keystone server found at #{keystone_host}")

template "/etc/neutron/api-paste.ini" do
  source "api-paste.ini.erb"
  owner node[:neutron][:platform][:user]
  group "root"
  mode "0640"
  variables(
    :keystone_protocol => keystone_protocol,
    :keystone_host => keystone_host,
    :keystone_service_port => keystone_service_port,
    :keystone_service_tenant => keystone_service_tenant,
    :keystone_service_user => keystone_service_user,
    :keystone_service_password => keystone_service_password,
    :keystone_admin_port => keystone_admin_port
  )
end


if node[:neutron][:use_ml2] && node[:neutron][:networking_plugin] != "vmware"
  plugin_cfg_path = "/etc/neutron/plugins/ml2/ml2_conf.ini"
else
  case node[:neutron][:networking_plugin]
  when "openvswitch", "cisco"
    agent_config_path = "/etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini"
  when "linuxbridge"
    agent_config_path = "/etc/neutron/plugins/linuxbridge/linuxbridge_conf.ini"
  when "vmware"
    agent_config_path = "/etc/neutron/plugins/nicira/nvp.ini"
  end

  plugin_cfg_path = agent_config_path
end

template "/etc/sysconfig/neutron" do
  source "sysconfig.neutron.erb"
  owner "root"
  group "root"
  mode 0640
  if node[:neutron][:networking_plugin] == "cisco" and node[:neutron][:use_ml2]
    variables(
      :plugin_config_file => plugin_cfg_path +  " /etc/neutron/plugins/ml2/ml2_conf_cisco.ini"
    )
  else
    variables(
      :plugin_config_file => plugin_cfg_path
    )
  end
  only_if { node[:platform] == "suse" }
  notifies :restart, "service[#{node[:neutron][:platform][:service_name]}]"
end

directory "/var/cache/neutron" do
 owner node[:neutron][:user]
 group node[:neutron][:group]
 mode 0755
 action :create
 only_if { node[:platform] == "ubuntu" }
end

file "/etc/default/neutron-server" do
  action :delete
  not_if { node[:platform] == "suse" }
  notifies :restart, "service[#{node[:neutron][:platform][:service_name]}]"
end


vlan_start = node[:network][:networks][:nova_fixed][:vlan]
vlan_end = vlan_start + 2000

if node[:neutron][:networking_plugin] == "cisco"
  mechanism_driver = "openvswitch,cisco_nexus"
else
  mechanism_driver = node[:neutron][:networking_plugin]
end

directory "/etc/neutron/plugins/ml2" do
  mode 0755
  action :create
  only_if { node[:platform] == "ubuntu" }
end

template plugin_cfg_path do
  source "ml2_conf.ini.erb"
  owner node[:neutron][:platform][:user]
  group "root"
  mode "0640"
  variables(
    :networking_mode => node[:neutron][:networking_mode],
    :mechanism_driver => mechanism_driver,
    :vlan_start => vlan_start,
    :vlan_end => vlan_end
  )
  only_if { node[:neutron][:use_ml2] && node[:neutron][:networking_plugin] != "vmware" }
end


if node[:neutron][:networking_plugin] == "cisco"
  include_recipe "neutron::cisco_support"
end


service node[:neutron][:platform][:service_name] do
  service_name "neutron-server" if node[:neutron][:use_gitrepo]
  supports :status => true, :restart => true
  action [:enable, :start]
  subscribes :restart, resources("template[/etc/neutron/api-paste.ini]")
  subscribes :restart, resources("template[#{plugin_cfg_path}]")
  subscribes :restart, resources("template[/etc/neutron/neutron.conf]")
end


include_recipe "neutron::api_register"
include_recipe "neutron::post_install_conf"


node[:neutron][:monitor] = {} if node[:neutron][:monitor].nil?
node[:neutron][:monitor][:svcs] = [] if node[:neutron][:monitor][:svcs].nil?
node[:neutron][:monitor][:svcs] << ["neutron"] if node[:neutron][:monitor][:svcs].empty?
node.save
