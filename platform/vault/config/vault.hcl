# Vault server configuration — file backend (persistent, no Raft complexity for Phase 0)
# Phase 1: migrate to Raft HA + AWS KMS auto-unseal

ui = true

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true   # TLS terminated at Caddy/Cloudflare — internal only
}

storage "file" {
  path = "/vault/data"
}

log_level = "info"
log_file  = "/vault/logs/vault.log"

# Disable mlock for Docker (kernel capability IPC_LOCK handles this)
disable_mlock = false

# Telemetry — expose to OTEL collector
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname          = true
}
