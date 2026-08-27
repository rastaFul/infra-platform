# Vault policy: artists tenant
# Access: read-only to artists secret path ONLY
# Any other path: implicit deny

path "secret/data/artists/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/artists/*" {
  capabilities = ["list"]
}

# Explicitly deny cross-tenant access (defense in depth)
path "secret/data/vetcare/*"       { capabilities = ["deny"] }
path "secret/data/rastafinancas/*" { capabilities = ["deny"] }
path "secret/data/microgrow/*"     { capabilities = ["deny"] }
