def upgrade ta, td, a, d
  a['use_external_dhcp'] = ta['use_external_dhcp']

  return a, d
end

def downgrade ta, td, a, d
  a.delete('use_external_dhcp')

  return a, d
end
