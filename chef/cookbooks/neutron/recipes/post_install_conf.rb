# Copyright 2011 Dell, Inc.
# Copyright 2015 SUSE Linux GmbH
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
require 'ipaddr'

def mask_to_bits(mask)
  IPAddr.new(mask).to_i.to_s(2).count("1")
end

fixed_net = node[:network][:networks]["nova_fixed"]
fixed_range = "#{fixed_net["subnet"]}/#{mask_to_bits(fixed_net["netmask"])}"
fixed_pool_start = fixed_net[:ranges][:dhcp][:start]
fixed_pool_end = fixed_net[:ranges][:dhcp][:end]
fixed_first_ip = IPAddr.new("#{fixed_range}").to_range().to_a[2]
fixed_last_ip = IPAddr.new("#{fixed_range}").to_range().to_a[-2]

fixed_pool_start = fixed_first_ip if fixed_first_ip > fixed_pool_start
fixed_pool_end = fixed_last_ip if fixed_last_ip < fixed_pool_end

public_net = node[:network][:networks]["public"]
floating_net = node[:network][:networks]["nova_floating"]

public_net_addr = IPAddr.new("#{public_net["subnet"]}/#{public_net["netmask"]}")
floating_net_addr = IPAddr.new("#{floating_net["subnet"]}/#{floating_net["netmask"]}")

# For backwards compatibility, if floating is a subnet of public use the
# router and range/netmask from public (otherwise router creation will fail)
if public_net_addr.include?(floating_net_addr)
  floating_router = public_net["router"]
  floating_range = "#{public_net["subnet"]}/#{mask_to_bits(public_net["netmask"])}"
else
  floating_router = floating_net["router"]
  floating_range = "#{floating_net["subnet"]}/#{mask_to_bits(floating_net["netmask"])}"
end
floating_pool_start = floating_net[:ranges][:host][:start]
floating_pool_end = floating_net[:ranges][:host][:end]

vni_start = [node[:neutron][:vxlan][:vni_start], 0].max

keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)

neutron_insecure = node[:neutron][:api][:protocol] == 'https' && node[:neutron][:ssl][:insecure]
ssl_insecure = keystone_settings['insecure'] || neutron_insecure

neutron_args = "--os-username '#{keystone_settings['service_user']}'"
neutron_args = "#{neutron_args} --os-password '#{keystone_settings['service_password']}'"
neutron_args = "#{neutron_args} --os-tenant-name '#{keystone_settings['service_tenant']}'"
neutron_args = "#{neutron_args} --os-auth-url '#{keystone_settings['internal_auth_url']}'"
neutron_args = "#{neutron_args} --os-region-name '#{keystone_settings['endpoint_region']}'"
if node[:platform] == "suse" or node[:neutron][:use_gitrepo]
  # these options are backported in SUSE packages, but not in Ubuntu
  neutron_args = "#{neutron_args} --endpoint-type internalURL"
  neutron_args = "#{neutron_args} --insecure" if ssl_insecure
end
if keystone_settings['api_version'] != "2.0"
  neutron_args = "#{neutron_args} --os-user-domain-name Default"
  neutron_args = "#{neutron_args} --os-project-domain-name Default"
end
neutron_cmd = "neutron #{neutron_args}"

fixed_network_type = ""
floating_network_type = ""

networking_plugin = node[:neutron][:networking_plugin]
ml2_type_drivers_default_provider_network = node[:neutron][:ml2_type_drivers_default_provider_network]
case networking_plugin
when 'ml2'
  # find the network node, to figure out the right "physnet" parameter
  network_node = NeutronHelper.get_network_node_from_neutron_attributes(node)
  ext_physnet_map = NeutronHelper.get_neutron_physnets(network_node, ["nova_floating"])
  floating_network_type = "--provider:network_type flat " \
    "--provider:physical_network #{ext_physnet_map["nova_floating"]}"
  case ml2_type_drivers_default_provider_network
  when 'vlan'
    fixed_network_type = "--provider:network_type vlan --provider:segmentation_id #{fixed_net["vlan"]} --provider:physical_network physnet1"
  when 'gre'
    fixed_network_type = "--provider:network_type gre --provider:segmentation_id 1"
  when 'vxlan'
    fixed_network_type = "--provider:network_type vxlan --provider:segmentation_id #{vni_start}"
  else
    Chef::Log.error("default provider network ml2 type driver '#{ml2_type_drivers_default_provider_network}' invalid for creating provider networks")
  end

  # *START* workaround for https://bugzilla.suse.com/show_bug.cgi?id=967009
  unless node[:neutron][:floating_router_fix]
    cookbook_file "crowbar-fix-floating-provider-attributes" do
      source "crowbar-fix-floating-provider-attributes"
      path "/usr/bin/crowbar-fix-floating-provider-attributes"
      mode "0755"
      only_if "out=$(#{neutron_cmd} net-show floating -f value -F provider:network_type); " \
        "[ $? == 0 ] && [ ${out} != \"flat\" ]"
    end

    # This adjusts the provider attributes of the existing "floating" network
    # to actually match what we want ("flat" network on the correct physnet)
    execute "fix floating network provider attributes" do
      command "/usr/bin/crowbar-fix-floating-provider-attributes " \
        "--physnet #{ext_physnet_map["nova_floating"]} --segmentation_id 0 --type flat " \
        "--tenant_id #{keystone_settings['service_tenant_id']} --network floating"
      action :run
      only_if "out=$(#{neutron_cmd} net-show floating -f value -F provider:network_type); " \
        "[ $? == 0 ] && [ ${out} != \"flat\" ]"
    end

    file "/usr/bin/crowbar-fix-floating-provider-attributes" do
      action :delete
    end

    if node[:neutron][:ml2_mechanism_drivers].include?("openvswitch")
      # In case the router was created after https://bugzilla.suse.com/show_bug.cgi?id=946882
      # was fixed, we likely had the wrong bridge mappings in the config and the
      # gateway port is in a "binding_failed" state. This tries to reset the port.
      cookbook_file "crowbar-fix-router-port-binding" do
        source "crowbar-fix-router-port-binding"
        path "/usr/bin/crowbar-fix-router-port-binding"
        mode "0755"
      end

      execute "reset port binding for floating network (bsc#967009)" do
        command "/usr/bin/crowbar-fix-router-port-binding --router router-floating"
        action :run
        only_if "out=$(#{neutron_cmd} router-list); [ $? != 0 ] || echo ${out} | grep -q router-floating"
      end

      file "/usr/bin/crowbar-fix-router-port-binding" do
        action :delete
      end
    end

    ruby_block "mark node for having the floating network fixed (bsc#967009)" do
      block do
        node[:neutron][:floating_router_fix] = true
        node.save
      end
    end
  end
  # *END* workaround for https://bugzilla.suse.com/show_bug.cgi?id=967009

when 'vmware'
  fixed_network_type = ""
  # We would like to be sure that floating network will be created
  # without any additional options, NSX will take care about everything.
  floating_network_type = ""
else
  Chef::Log.error("networking plugin '#{networking_plugin}' invalid for creating provider networks")
end


execute "create_fixed_network" do
  command "#{neutron_cmd} net-create fixed --shared #{fixed_network_type}"
  not_if "out=$(#{neutron_cmd} net-list); [ $? != 0 ] || echo ${out} | grep -q ' fixed '"
  retries 5
  retry_delay 10
  action :nothing
end

execute "create_floating_network" do
  command "#{neutron_cmd} net-create floating --router:external=True #{floating_network_type}"
  not_if "out=$(#{neutron_cmd} net-list); [ $? != 0 ] || echo ${out} | grep -q ' floating '"
  retries 5
  retry_delay 10
  action :nothing
end

dns_options = ""
if node[:neutron][:use_infoblox]
    dns_options = node[:neutron][:infoblox][:ib_dnsserver].map{ |s| "--dns-nameserver #{s}" }.join(" ")
end

execute "create_fixed_subnet" do
  command "#{neutron_cmd} subnet-create --name fixed --allocation-pool start=#{fixed_pool_start},end=#{fixed_pool_end} fixed #{fixed_range} #{dns_options}"
  not_if "out=$(#{neutron_cmd} subnet-list); [ $? != 0 ] || echo ${out} | grep -q ' fixed '"
  retries 5
  retry_delay 10
  action :nothing
end

execute "create_floating_subnet" do
  command "#{neutron_cmd} subnet-create --name floating --allocation-pool start=#{floating_pool_start},end=#{floating_pool_end} --gateway #{floating_router} floating #{floating_range} --enable_dhcp False"
  not_if "out=$(#{neutron_cmd} subnet-list); [ $? != 0 ] || echo ${out} | grep -q ' floating '"
  retries 5
  retry_delay 10
  action :nothing
end

execute "create_router" do
  command "#{neutron_cmd} router-create router-floating"
  not_if "out=$(#{neutron_cmd} router-list); [ $? != 0 ] || echo ${out} | grep -q router-floating"
  retries 5
  retry_delay 10
  action :nothing
end

execute "set_router_gateway" do
  command "#{neutron_cmd} router-gateway-set router-floating floating"
  not_if "out=$(#{neutron_cmd} router-show router-floating -f shell) ; [ $? != 0 ] || eval $out && [ \"${external_gateway_info}\" != \"\" ]"
  retries 5
  retry_delay 10
  action :nothing
end

execute "add_fixed_network_to_router" do
  command "#{neutron_cmd} router-interface-add router-floating fixed"
  not_if "out1=$(#{neutron_cmd} subnet-show -f shell fixed) ; rc1=$?; eval $out1 ; out2=$(#{neutron_cmd} router-port-list router-floating); [ $? != 0 ] || [ $rc1 != 0 ] || echo $out2 | grep -q $id"
  retries 5
  retry_delay 10
  action :nothing
end

execute "Neutron network configuration" do
  command "#{neutron_cmd} net-list &>/dev/null"
  retries 5
  retry_delay 10
  action :nothing
  notifies :run, "execute[create_fixed_network]", :delayed
  notifies :run, "execute[create_floating_network]", :delayed
  notifies :run, "execute[create_fixed_subnet]", :delayed
  notifies :run, "execute[create_floating_subnet]", :delayed
  notifies :run, "execute[create_router]", :delayed
  notifies :run, "execute[set_router_gateway]", :delayed
  notifies :run, "execute[add_fixed_network_to_router]", :delayed
end

# This is to trigger all the above "execute" resources to run :delayed, so that
# they run at the end of the chef-client run, after the neutron service has been
# restarted (in case of a config change)
execute "Trigger Neutron network configuration" do
  command "true"
  notifies :run, "execute[Neutron network configuration]", :delayed
end

