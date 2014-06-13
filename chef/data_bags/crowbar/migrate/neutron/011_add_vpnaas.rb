def upgrade ta, td, a, d
  unless a.include?('use_vpnaas')
    a['use_vpnaas'] = ta['use_vpnaas']
  end
  return a, d
end

def downgrade ta, td, a, d
  a.delete('use_vpnaas')
  return a, d
end
