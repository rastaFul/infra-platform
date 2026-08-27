# Observability Contract

Every service in the platform MUST implement this contract. No exceptions.

---

## Health Endpoint

```
GET /health
```

Response: `200 OK` (always — even when degraded, so load balancer keeps routing)

```json
{
  "status": "ok" | "degraded" | "down",
  "version": "1.2.3",
  "uptime": 3600,
  "deps": {
    "database": "ok",
    "redis": "degraded",
    "vault": "ok"
  }
}
```

Rules:
- `status: "ok"` — all deps healthy
- `status: "degraded"` — service running, at least one dep unhealthy but service still responds
- `status: "down"` — service cannot serve requests (rare: usually the process is dead)
- `uptime` — seconds since process start
- `deps` — key per external dependency, value is `"ok" | "degraded" | "down"`

HTTP status codes:
- `200` for `ok` and `degraded` (keep load balancer routing)
- `503` for `down`

---

## Metrics Endpoint

```
GET /metrics
```

Response: Prometheus text format (Content-Type: `text/plain; version=0.0.4`)

Required metrics (via `prom-client`):

```
# Request rate
http_requests_total{method, route, status_code, service}

# Latency histogram (milliseconds)
http_request_duration_ms_bucket{method, route, status_code, service, le}
http_request_duration_ms_sum{method, route, status_code, service}
http_request_duration_ms_count{method, route, status_code, service}

# Default Node.js metrics (from prom-client.collectDefaultMetrics())
process_cpu_seconds_total
process_resident_memory_bytes
nodejs_eventloop_lag_seconds
```

---

## Structured Logging

All log lines MUST be JSON. No plain text logs.

Required fields:
```json
{
  "level": "info" | "warn" | "error" | "debug",
  "msg": "human readable message",
  "service": "vetcare-api",
  "version": "1.2.3",
  "traceId": "4bf92f3577b34da6a3ce929d0e0e4736",
  "spanId": "00f067aa0ba902b7",
  "timestamp": "2026-08-12T10:00:00.000Z"
}
```

`traceId` and `spanId` are injected automatically by the OTEL SDK. Use a logger that reads from the active span context (e.g., `pino` with OTEL context propagation).

---

## Error Reporting

Report errors to GlitchTip via the OTEL SDK (not direct Sentry SDK).

```typescript
import { trace } from '@opentelemetry/api';

// In error handler:
const span = trace.getActiveSpan();
span?.recordException(error);
span?.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
```

GlitchTip receives errors via the OTEL Collector's trace pipeline (OTLP → GlitchTip OTLP endpoint, Phase 1).

---

## OTEL Configuration

Environment variables every service MUST set:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318   # local; configurable per env
OTEL_SERVICE_NAME=<project>-<service>                # e.g., vetcare-api
OTEL_RESOURCE_ATTRIBUTES=service.version=<version>,deployment.environment=local
```

Local endpoint: `http://localhost:4318` (OTLP HTTP)
Production endpoint: set via `OTEL_EXPORTER_OTLP_ENDPOINT` environment variable

---

## Ports Reserved by Platform

| Port  | Service          | Protocol |
|-------|------------------|----------|
| 4317  | OTEL Collector   | gRPC     |
| 4318  | OTEL Collector   | HTTP     |
| 8200  | Vault            | HTTP     |
| 3100  | Loki             | HTTP     |
| 8086  | InfluxDB         | HTTP     |
| 3010  | Grafana          | HTTP     |
| 8010  | GlitchTip        | HTTP     |
| 8888  | OTEL Metrics     | HTTP     |
