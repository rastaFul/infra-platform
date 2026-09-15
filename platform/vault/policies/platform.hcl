# Vault policy: platform tenant (shared observability + secrets stack itself,
# not a product). Access: read-only to secret/data/platform/* ONLY.
# Created 2026-09-15 (infra-full-upgrade-2026-09-followups T2, D-2026-09-15-2/3
# item 4) -- closes the gap where platform-level secrets (Grafana admin
# password, GlitchTip secret key/db password, InfluxDB tokens) lived only in
# platform/.env, never pushed to Vault like the 4 product tenants already are.

path "secret/data/platform/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/platform/*" {
  capabilities = ["list"]
}

# Explicitly deny cross-tenant access (defense in depth, same pattern as
# every other tenant policy in this directory)
path "secret/data/vetcare/*"       { capabilities = ["deny"] }
path "secret/data/rastafinancas/*" { capabilities = ["deny"] }
path "secret/data/microgrow/*"     { capabilities = ["deny"] }
path "secret/data/artists/*"       { capabilities = ["deny"] }
