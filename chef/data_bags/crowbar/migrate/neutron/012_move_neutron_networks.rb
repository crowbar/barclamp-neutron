def upgrade ta, td, a, d
  a['networks'] = {}

  ['floating', 'fixed'].each do |name|
    # Import nova networks definitions from data bags
    db = ProposalObject.find_data_bag_item "crowbar/nova_#{name}_network"
    unless db.nil?
      a['networks'][name] = db['network']
      a['networks'][name].delete('node')
      a['networks'][name].delete('usage')
      a['networks'][name].delete('add_bridge')
      a['networks'][name].delete('router_pref')
      if name == 'fixed'
        a['networks'][name]['external'] = false
      else
        a['networks'][name]['external'] = true
      end
      db.destroy
    end
  end
  
  Chef::Search::Query.new.search(:node, "roles:neutron-server AND roles:neutron-config-*") do |neutron|
    unless neutron.nil?
      # Save network definitions on neutron servers 
      neutron['neutron']['networks'] = a['networks']
      neutron.save
      ['floating', 'fixed'].each do |name|
        # Create new data bag with neutron networks
        db = ProposalObject.find_data_bag_item "crowbar/#{name}_network"
        if db.nil?
          bc = Chef::DataBagItem.new
          bc.data_bag 'crowbar'
          bc['id'] = "#{name}_network"
          bc['network'] = a['networks'][name]
          bc['allocated'] = {}
          bc['allocated_by_name'] = {}
          db = ProposalObject.new bc
          db.save
        end
      end
      # Enable interface for fixed network
      if neutron['neutron']['networking_mode'] == 'vlan'
        Chef::Search::Query.new.search(:node, "roles:neutron-l3 OR roles:nova-multi-*") do |node|
          node['crowbar']['network']['fixed'] = a['networks']['fixed']
          node['crowbar']['network']['fixed']['usage'] = 'fixed'
          node['crowbar']['network']['fixed']['node'] = node.name
          node['crowbar']['network']['fixed']['use_vlan'] = false
          node['crowbar']['network'].delete('nova_fixed')
          node['crowbar_wall']['network']['nets']['fixed'] = node['crowbar_wall']['network']['nets']['nova_fixed']
          node['crowbar_wall']['network']['nets'].delete('nova_fixed')
          node.save
        end
      end
    end
  end

  return a, d
end

def downgrade ta, td, a, d
  a['networks'].delete

  return a, d
end
