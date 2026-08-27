# Tutorial 02 — Add a New Project to the Platform

**Goal:** Connect a new project (e.g., `myapp`) to platform services (Vault, OTEL, Loki).

**Time:** ~20 minutes

**Prerequisites:** Tutorial 01 complete, platform stack running.

---

## Step 1 — Create the project directory

```bash
mkdir -p ~/projects/infra-platform/projects/myapp
```

---

## Step 2 — Create project Docker network and compose file

Create `~/projects/myapp/infra/docker-compose.yml`:

```yaml
networks:
  myapp_net:
    name: myapp_net
    driver: bridge
  platform_net:
    name: platform_net
    external: true  # owned by services/platform/

services:
  myapp-api:
    build: ../
    container_name: myapp-api
    networks:
      - myapp_net
      - platform_net   # needed to reach Vault, Loki, OTEL Collector
    ports:
      - "127.0.0.1:3007:3000"
    environment:
      - VAULT_ADDR=http://vault:8200
      - VAULT_ROLE_ID=${VAULT_ROLE_ID}
      - VAULT_SECRET_ID=${VAULT_SECRET_ID}
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
      - OTEL_SERVICE_NAME=myapp-api
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
```

---

## Step 3 — Add Vault policy

Create `~/projects/infra-platform/platform/vault/policies/myapp.hcl`:

```hcl
path "secret/data/myapp/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/myapp/*" {
  capabilities = ["list"]
}

# Deny all other tenants
path "secret/data/vetcare/*"       { capabilities = ["deny"] }
path "secret/data/rastafinancas/*" { capabilities = ["deny"] }
path "secret/data/microgrow/*"     { capabilities = ["deny"] }
path "secret/data/artists/*"       { capabilities = ["deny"] }
```

---

## Step 4 — Register the AppRole in Vault

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(jq -r '.root_token' ~/.vault-init-local)

# Apply policy
vault policy write myapp ~/projects/infra-platform/platform/vault/policies/myapp.hcl

# Create AppRole
vault write auth/approle/role/myapp \
  policies=myapp \
  token_ttl=1h \
  token_max_ttl=4h

# Get credentials
ROLE_ID=$(vault read -field=role_id auth/approle/role/myapp/role-id)
SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/myapp/secret-id)

echo "VAULT_ROLE_ID=${ROLE_ID}"
echo "VAULT_SECRET_ID=${SECRET_ID}"
```

Add these to your project's `.env` file.

---

## Step 5 — Write initial secrets

```bash
vault kv put secret/myapp/db \
  url="postgresql://localhost:5432/myapp" \
  password="changeme"
```

---

## Step 6 — Instrument the app

Install OTEL SDK:
```bash
npm install @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node
```

Create `src/instrumentation.ts` (load before everything else):
```typescript
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';

const sdk = new NodeSDK({
  instrumentations: [getNodeAutoInstrumentations()],
});
sdk.start();
```

Set environment variables:
```
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_SERVICE_NAME=myapp-api
OTEL_RESOURCE_ATTRIBUTES=service.version=0.1.0,deployment.environment=local
```

---

## Step 7 — Verify

```bash
# Start the project
cd ~/projects/myapp/infra
docker compose --env-file .env up -d

# Check health
curl http://localhost:3007/health

# Verify logs in Loki (Grafana → Explore → Loki → {service="myapp-api"})
```
