def upgrade ta, td, a, d
  a['use_infoblox'] = ta['use_infoblox']
  a['infoblox'] = {}
  a['infoblox']['ib_wapi'] = ta['infoblox']['ib_wapi'] 
  a['infoblox']['ib_username'] = ta['infoblox']['ib_username']
  a['infoblox']['ib_password'] = ta['infoblox']['ib_password']
  a['infoblox']['ib_external_network_view'] = ta['infoblox']['ib_external_network_view']
  a['infoblox']['ib_default_network_view'] = ta['infoblox']['ib_default_network_view']
  a['infoblox']['ib_members'] = ta['infoblox']['ib_members']
  a['infoblox']['ib_fqdn_suffix'] = ta['infoblox']['ib_fqdn_suffix']
  a['infoblox']['ib_dnsserver'] = ta['infoblox']['ib_dnsserver']
  a['infoblox']['use_host_records_for_ip_allocation'] = ta['infoblox']['use_host_records_for_ip_allocation']
  a['infoblox']['enable_dhcp_relay'] = ta['infoblox']['enable_dhcp_relay']
  return a, d
end

def downgrade ta, td, a, d
  a.delete('use_infoblox')
  a.delete('infoblox')
  return a, d
end
