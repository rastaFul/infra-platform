# Vault policy: vetcare tenant
# Access: read-only to vetcare secret path ONLY
# Any other path: implicit deny

path "secret/data/vetcare/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/vetcare/*" {
  capabilities = ["list"]
}

# Explicitly deny cross-tenant access (defense in depth)
path "secret/data/rastafinancas/*" { capabilities = ["deny"] }
path "secret/data/microgrow/*"     { capabilities = ["deny"] }
path "secret/data/artists/*"       { capabilities = ["deny"] }
path "secret/data/platform/*" { capabilities = ["deny"] }
