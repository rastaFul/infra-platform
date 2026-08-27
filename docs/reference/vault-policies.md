# Vault Policies Reference

## Policy Structure

Each tenant (project) has one Vault policy. Policies are stored in `platform/vault/policies/<project>.hcl`.

## Capability Matrix

| Project      | `secret/data/<project>/*` | All other tenant paths |
|--------------|--------------------------|----------------------|
| vetcare      | read, list               | deny                 |
| rastafinancas| read, list               | deny                 |
| microgrow    | read, list               | deny                 |
| artists      | read, list               | deny                 |

## AppRole Configuration

Each project has one AppRole bound to its policy:

| Parameter        | Value          | Notes |
|-----------------|----------------|-------|
| `token_ttl`     | 1h             | Rotate token every hour |
| `token_max_ttl` | 4h             | Hard ceiling |
| `secret_id_ttl` | 0 (local), 24h (prod) | 0 = no expiry for local dev |
| `policies`      | `<project>`    | Only own policy |

## Secret Path Convention

```
secret/data/<project>/<category>/<key>

Examples:
  secret/data/vetcare/db/url
  secret/data/vetcare/db/password
  secret/data/vetcare/external/stripe_key
  secret/data/rastafinancas/db/url
  secret/data/microgrow/influxdb/token
```

## Managing Secrets

Write a secret (operator only, root or admin token):
```bash
vault kv put secret/vetcare/db url="postgresql://..." password="..."
```

Read a secret (app, with AppRole token):
```bash
vault kv get -field=password secret/vetcare/db
```

## AppRole Authentication Flow (app side)

```bash
# 1. Get token using role-id and secret-id
VAULT_TOKEN=$(vault write -field=token auth/approle/login \
  role_id="${VAULT_ROLE_ID}" \
  secret_id="${VAULT_SECRET_ID}")

# 2. Read secret
SECRET=$(VAULT_TOKEN="${VAULT_TOKEN}" vault kv get -field=value secret/vetcare/db/password)
```

For Node.js: use `node-vault` or `@hashicorp/vault-client` SDK.
