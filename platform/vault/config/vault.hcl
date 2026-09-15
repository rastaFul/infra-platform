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

# disable_mlock = true (changed 2026-09-15, infra-full-upgrade-2026-09 Lote 7,
# bump to Vault 2.1.0): Vault 2.x images removed the cap_ipc_lock capability
# at build time -- granting `cap_add: IPC_LOCK` in the compose file (kept for
# documentation, has no effect anymore) no longer lets the binary call
# mlock(). With disable_mlock still `false`, that mlock() call fails and
# Vault refuses to start. Same tradeoff Vault's own install docs recommend
# for containerized/non-swap environments generally.
disable_mlock = true

# Telemetry — expose to OTEL collector
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname          = true
}
