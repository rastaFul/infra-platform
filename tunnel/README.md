# CloudFlare Tunnel

Manages the single CloudFlare tunnel for all local services.

## Routes

| Hostname | Service | Port |
|----------|---------|------|
| financas.rastaful.dev | rastafinancas-web | 3000 |
| grow.rastaful.dev | microgrow-webapp | 3002 |
| grow-sim.rastaful.dev | microgrow-webapp-sim | 3003 |
| grow-api.rastaful.dev | microgrow-api | 4000 |
| metrics.rastaful.dev | platform-grafana | 3010 |

> Note: grow-mqtt.rastaful.dev intentionally removed — MQTT WebSocket must not be publicly exposed.

## Start

```bash
pm2 start /home/rodrigo/services/tunnel/pm2.config.js
```

## Stop old tunnel (one-time migration)

```bash
pm2 stop rastafinancas-tunnel
pm2 delete rastafinancas-tunnel
# Then: edit ~/projects/rastafinancas/ecosystem.config.js to remove the tunnel app entry
pm2 start /home/rodrigo/services/tunnel/pm2.config.js
```

## Credentials

Tunnel credentials remain at `~/.cloudflared/` (managed by cloudflared).
This config just references them by path.

## Cloud Migration

When moving to AWS:
- Replace with ALB + Route53 + CloudFront
- Each service gets its own target group
- ACM manages TLS certificates
- WAF rules replace CloudFlare security features
