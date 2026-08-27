# Network Topology

## Docker Networks

```
platform_net (bridge)
  owner: ~/projects/services/platform/docker-compose.yml
  services: influxdb, grafana, loki, glitchtip, vault, otel-collector
  external: true (all other compose files join this network)

microgrow_net (bridge)
  owner: ~/projects/microgrow/infra/docker-compose.yml
  services: mosquitto, telegraf, promtail, simulator
  cross-connects: telegraf → platform_net (influxdb), promtail → platform_net (loki)

vetcare_net (bridge) — future
rastafinancas_net (bridge) — future
artists_net (bridge) — future
```

## Port Map

| Port  | Host Binding  | Service             | Project    |
|-------|--------------|---------------------|------------|
| 3000  | 127.0.0.1    | rastafinancas-web   | app        |
| 3001  | 127.0.0.1    | rastafinancas-api   | app        |
| 3002  | 127.0.0.1    | microgrow-webapp    | app        |
| 3003  | 127.0.0.1    | microgrow-webapp-sim| app        |
| 3004  | 127.0.0.1    | vetcare             | app        |
| 3005  | 127.0.0.1    | artists-web         | app        |
| 3006  | 127.0.0.1    | artists-api         | app        |
| 3010  | 127.0.0.1    | Grafana             | platform   |
| 3100  | 127.0.0.1    | Loki                | platform   |
| 4000  | 127.0.0.1    | microgrow-api       | app        |
| 4317  | 127.0.0.1    | OTEL Collector gRPC | platform   |
| 4318  | 127.0.0.1    | OTEL Collector HTTP | platform   |
| 8010  | 127.0.0.1    | GlitchTip           | platform   |
| 8086  | 127.0.0.1    | InfluxDB            | platform   |
| 8200  | 127.0.0.1    | Vault               | platform   |
| 8888  | 127.0.0.1    | OTEL Metrics        | platform   |
| 1883  | 127.0.0.1    | Mosquitto MQTT      | microgrow  |
| 9001  | 127.0.0.1    | Mosquitto WS        | microgrow  |

All host bindings are `127.0.0.1` (WSL2 localhost only). Public exposure is via Cloudflare Tunnel only.

## Traffic Flow

```
Internet → Cloudflare (TLS, WAF, DDoS)
                ↓
         Cloudflare Tunnel (running on WSL2 host)
                ↓
         localhost:<port> (app)
                ↓
         app → OTEL Collector :4318 (telemetry)
         app → Vault :8200 (secrets, at startup)
         app → platform services (via platform_net)
```
