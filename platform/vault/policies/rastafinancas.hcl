# Vault policy: rastafinancas tenant
# Access: read-only to rastafinancas secret path ONLY
# Any other path: implicit deny

path "secret/data/rastafinancas/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/rastafinancas/*" {
  capabilities = ["list"]
}

# Explicitly deny cross-tenant access (defense in depth)
path "secret/data/vetcare/*"   { capabilities = ["deny"] }
path "secret/data/microgrow/*" { capabilities = ["deny"] }
path "secret/data/artists/*"   { capabilities = ["deny"] }
