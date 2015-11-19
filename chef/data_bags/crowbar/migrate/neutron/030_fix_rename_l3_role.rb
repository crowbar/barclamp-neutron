def upgrade ta, td, a, d
  if d.fetch('elements_expanded', {}).has_key? 'neutron-l3'
    d['elements_expanded']['neutron-network'] = d['elements_expanded']['neutron-l3']
    d['elements_expanded'].delete('neutron-l3')
  end

  return a, d
end

def downgrade ta, td, a, d
  if d.fetch('elements_expanded', {}).has_key? 'neutron-network'
    d['elements_expanded']['neutron-l3'] = d['elements_expanded']['neutron-network']
    d['elements_expanded'].delete('neutron-network')
  end

  return a, d
end
