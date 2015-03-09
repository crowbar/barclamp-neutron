# Copyright 2014 SUSE
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

package node[:neutron][:platform][:ha_tool_pkg] unless node[:neutron][:platform][:ha_tool_pkg] == ""

use_l3_agent = (node[:neutron][:networking_plugin] != "vmware")
use_lbaas_agent = node[:neutron][:use_lbaas]
use_vpnaas_agent = node[:neutron][:use_vpnaas]

# Wait for all "neutron-l3" nodes to reach this point so we know that they will
# have all the required packages installed and configuration files updated
# before we create the pacemaker resources.
crowbar_pacemaker_sync_mark "sync-neutron-l3_before_ha"

# Avoid races when creating pacemaker resources
crowbar_pacemaker_sync_mark "wait-neutron-l3_ha_resources"

l3_agent_primitive = "neutron-l3-agent"
dhcp_agent_primitive = "neutron-dhcp-agent"
metadatda_agent_primitive = "neutron-metadata-agent"
metering_agent_primitive =  "neutron-metering-agent"
lbaas_agent_primitive =  "neutron-lbaas-agent"
vpnaas_agent_primitive =  "neutron-vpnaas-agent"

pacemaker_primitive l3_agent_primitive do
  agent node[:neutron][:ha][:l3][:l3_ra]
  op node[:neutron][:ha][:l3][:op]
  action [ :create ]
  only_if { use_l3_agent && CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

pacemaker_primitive dhcp_agent_primitive do
  agent node[:neutron][:ha][:l3][:dhcp_ra]
  op node[:neutron][:ha][:l3][:op]
  action [ :create ]
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

pacemaker_primitive metadatda_agent_primitive do
  agent node[:neutron][:ha][:l3][:metadata_ra]
  op node[:neutron][:ha][:l3][:op]
  action [ :create ]
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

pacemaker_primitive metering_agent_primitive do
  agent node[:neutron][:ha][:l3][:metering_ra]
  op node[:neutron][:ha][:l3][:op]
  action [ :create ]
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

pacemaker_primitive lbaas_agent_primitive do
  agent node[:neutron][:ha][:l3][:lbaas_ra]
  op node[:neutron][:ha][:l3][:op]
  action [ :create ]
  only_if { use_lbaas_agent && CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

pacemaker_primitive vpnaas_agent_primitive do
  agent node[:neutron][:ha][:l3][:vpnaas_ra]
  op node[:neutron][:ha][:l3][:op]
  action [ :create ]
end

networking_plugin = node[:neutron][:networking_plugin]

case networking_plugin
when 'ml2'
  ml2_mech_drivers = node[:neutron][:ml2_mechanism_drivers]
  case
  when ml2_mech_drivers.include?("openvswitch")
    neutron_agent = node[:neutron][:platform][:ovs_agent_name]
    neutron_agent_ra = node[:neutron][:ha][:l3]["openvswitch_ra"]
  when ml2_mech_drivers.include?("linuxbridge")
    neutron_agent = node[:neutron][:platform][:lb_agent_name]
    neutron_agent_ra = node[:neutron][:ha][:l3]["linuxbridge_ra"]
  end
when "vmware"
  neutron_agent = ''
  neutron_agent_ra = ''
end
neutron_agent_primitive = neutron_agent.sub(/^openstack-/, "")

pacemaker_primitive neutron_agent_primitive do
  agent neutron_agent_ra
  op node[:neutron][:ha][:l3][:op]
  action [ :create ]
  only_if { use_l3_agent && CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

group_members = []
group_members << l3_agent_primitive if use_l3_agent
group_members << lbaas_agent_primitive if use_lbaas_agent
group_members << vpnaas_agent_primitive if use_vpnaas_agent
group_members += [ dhcp_agent_primitive,
                   metadatda_agent_primitive,
                   metering_agent_primitive ]
group_members << neutron_agent_primitive if use_l3_agent

agents_group_name = "g-neutron-agents"
agents_clone_name = "cl-#{agents_group_name}"

pacemaker_group agents_group_name do
  members group_members
  action [ :create ]
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

pacemaker_clone agents_clone_name do
  rsc agents_group_name
  action [ :create, :start ]
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)

ha_tool_primitive_name = "neutron-ha-tool"

# FIXME: While the neutron-ha-tool resource agent allows specifying a CA
# Certificate to use for SSL Certificate verification, it's hard to select
# right CA file as we allow Keystone's and Neutron's to use different CAs.  So
# we just rely on the correct CA files being installed in a system wide default
# location.
pacemaker_primitive ha_tool_primitive_name do
  agent node[:neutron][:ha][:l3][:ha_tool_ra]
  params ({
    "os_auth_url"    => keystone_settings["internal_auth_url"],
    "os_tenant_name" => keystone_settings["admin_tenant"],
    "os_username"    => keystone_settings["admin_user"],
    "os_password"    => keystone_settings["admin_password"],
    "os_insecure"    => keystone_settings["insecure"] || node[:neutron][:ssl][:insecure]
  })
  op node[:neutron][:ha][:l3][:op]
  action [ :create, :start ]
  only_if { use_l3_agent && CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

crowbar_pacemaker_order_only_existing "o-#{ha_tool_primitive_name}" do
  ordering [ "g-haproxy", "cl-neutron-server", agents_clone_name, ha_tool_primitive_name ]
  score "Mandatory"
  action :create
  only_if { use_l3_agent && CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

crowbar_pacemaker_sync_mark "create-neutron-l3_ha_resources"
