def upgrade ta, td, a, d
  a['use_infoblox'] = ta['use_infoblox']
  a['infoblox'] = ta['infoblox']
  return a, d
end

def downgrade ta, td, a, d
  a.delete('use_infoblox')
  a.delete('infoblox')
  return a, d
end
