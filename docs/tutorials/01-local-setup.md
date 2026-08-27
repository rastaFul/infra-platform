# Tutorial 01 — Local Platform Setup

**Goal:** Start the full platform stack on your WSL2 machine and verify all services are healthy.

**Time:** ~15 minutes

**Prerequisites:**
- Docker Desktop running (or Docker Engine in WSL2)
- `jq`, `curl`, `vault` CLI installed
- Projects cloned to `~/projects/`

---

## Step 1 — Configure services/platform

```bash
cd ~/projects/services/platform
cp .env.example .env
# Edit .env — fill in all required passwords and tokens
nano .env
```

Required variables:
- `INFLUXDB_ADMIN_PASSWORD` — any strong password
- `INFLUXDB_ADMIN_TOKEN` — random 32+ char string
- `GRAFANA_ADMIN_PASSWORD` — any strong password
- `GLITCHTIP_DB_PASSWORD` — any strong password
- `GLITCHTIP_SECRET_KEY` — random 50+ char string

---

## Step 2 — Start the full stack

Use the provided script (handles startup order automatically):

```bash
cd ~/projects/infra-platform
bash scripts/platform-start.sh
```

This will:
1. Start services/platform (Grafana, InfluxDB, Loki, GlitchTip)
2. Wait for health checks to pass
3. Start infra-platform/platform (Vault, OTEL Collector)
4. Run `vault-init.sh` — initialize and unseal Vault, create AppRoles

---

## Step 3 — Verify services

```bash
# Platform core
curl -sf http://localhost:3010/api/health && echo "Grafana OK"
curl -sf http://localhost:3100/ready && echo "Loki OK"
curl -sf http://localhost:8086/health && echo "InfluxDB OK"
curl -sf http://localhost:8010/api/0/projects/ -o /dev/null -w "%{http_code}" && echo "GlitchTip OK"

# Vault
curl -sf http://localhost:8200/v1/sys/health | jq '{initialized,sealed}'

# OTEL Collector
curl -sf http://localhost:8888/metrics | head -5
```

Expected:
```
Grafana OK
Loki OK
InfluxDB OK
200 GlitchTip OK
{
  "initialized": true,
  "sealed": false
}
```

---

## Step 4 — Access UIs

| Service    | URL                        | Credentials |
|------------|----------------------------|-------------|
| Grafana    | http://localhost:3010       | admin / (your GRAFANA_ADMIN_PASSWORD) |
| Vault UI   | http://localhost:8200/ui    | root token from ~/.vault-init-local |
| GlitchTip  | http://localhost:8010       | Create account on first visit |
| InfluxDB   | http://localhost:8086       | admin / (your INFLUXDB_ADMIN_PASSWORD) |

---

## Step 5 — Inspect Vault AppRoles

The `platform-start.sh` script printed `role_id` and `secret_id` for each project. You can retrieve them again:

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(jq -r '.root_token' ~/.vault-init-local)

# List all AppRoles
vault list auth/approle/role

# Get role-id for vetcare
vault read auth/approle/role/vetcare/role-id

# Generate a new secret-id
vault write -f auth/approle/role/vetcare/secret-id
```

---

## Stopping the Stack

```bash
bash ~/projects/infra-platform/scripts/platform-stop.sh
```

Note: Vault data is persistent (`vault_data` Docker volume). After restarting, Vault will be initialized but sealed — run `platform-start.sh` again to unseal automatically.

---

## Next Steps

- [Tutorial 02 — Add a New Project](./02-add-new-project.md)
- [Tutorial 03 — First AWS Deploy](./03-first-aws-deploy.md)
- [Reference: Observability Contract](../reference/observability-contract.md)
