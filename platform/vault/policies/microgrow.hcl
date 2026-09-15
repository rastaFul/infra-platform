# Vault policy: microgrow tenant
# Access: read-only to microgrow secret path ONLY
# Any other path: implicit deny

path "secret/data/microgrow/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/microgrow/*" {
  capabilities = ["list"]
}

# Explicitly deny cross-tenant access (defense in depth)
path "secret/data/vetcare/*"       { capabilities = ["deny"] }
path "secret/data/rastafinancas/*" { capabilities = ["deny"] }
path "secret/data/artists/*"       { capabilities = ["deny"] }
path "secret/data/platform/*" { capabilities = ["deny"] }
