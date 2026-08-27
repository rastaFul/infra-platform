# How-To: Rotate a Vault Secret

**When:** Compromised credentials, scheduled rotation, or app secret update.

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(jq -r '.root_token' ~/.vault-init-local)  # or admin token

# Write new secret value (KV v2 keeps version history)
vault kv put secret/<project>/db password="new-password-here"

# Verify
vault kv get secret/<project>/db

# If app reads secret at startup only: restart the app/container
docker compose restart <service>

# To rollback to previous version:
vault kv rollback -version=<N> secret/<project>/db
```

**AppRole secret-id rotation** (if secret-id is compromised):

```bash
# Revoke all existing secret-ids for the role
vault write -f auth/approle/role/<project>/secret-id-accessor/destroy \
  secret_id_accessor=<accessor>

# Or destroy all:
vault list auth/approle/role/<project>/secret-id | \
  xargs -I{} vault write -f auth/approle/role/<project>/secret-id-accessor/destroy \
    secret_id_accessor={}

# Generate new secret-id
vault write -f auth/approle/role/<project>/secret-id
```
