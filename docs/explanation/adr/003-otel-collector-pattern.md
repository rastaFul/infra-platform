# ADR 003 — OpenTelemetry Collector as Observability Gateway

**Status:** ACCEPTED
**Date:** 2026-08-12
**Deciders:** rodrigob.dev@gmail.com

---

## Context

The platform needs observability from day 0 across all projects (vetcare, rastafinancas, microgrow, artists). Requirements:
- Unified pipeline for traces, metrics, and logs
- Backend-agnostic: ability to swap Loki → Datadog, Prometheus → Mimir, without app code changes
- No vendor SDK lock-in in application code
- Cost-efficient: avoid paying for ingestion during development

## Decision

Instrument all apps with the **OpenTelemetry SDK** (language-native) and route all telemetry through a central **OpenTelemetry Collector** on `platform_net`.

App → OTEL SDK → OTEL Collector → backends (Loki, Prometheus, Tempo)

The Collector is the only component that knows about backends. Apps only know `OTEL_EXPORTER_OTLP_ENDPOINT`.

### Phase 0 (current)

| Signal  | Exporter | Backend   | Notes |
|---------|----------|-----------|-------|
| Traces  | debug    | (dropped) | SDK instrumented now; Tempo added in Phase 1 |
| Metrics | prometheus | Prometheus scrape at :8889 | Grafana scrapes this |
| Logs    | loki     | Loki      | Structured JSON via OTLP |

### Phase 1

Add Grafana Tempo. Change `traces` pipeline exporter from `debug` to `otlp/tempo`. Zero app code change required.

## Consequences

**Positive:**
- Zero app code changes to swap backends — change Collector config only
- Single ingestion point: rate limiting, sampling, and batching in one place
- Memory limiter processor prevents Collector from OOM-killing under spike
- Collector health exposed at `:8888/metrics` (self-observability)

**Negative:**
- Phase 0 traces are dropped — no distributed tracing until Phase 1
- Collector is a new dependency in the startup order
- gRPC (4317) vs HTTP (4318) selection left to SDK configuration

## Instrumentation Contract

Every service MUST set:
```
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_SERVICE_NAME=<project>-<service>
OTEL_RESOURCE_ATTRIBUTES=service.version=<version>,deployment.environment=local
```

See `docs/reference/observability-contract.md` for the full contract.

## References

- [OTEL Collector contrib](https://github.com/open-telemetry/opentelemetry-collector-contrib)
- [Loki OTLP exporter](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/lokiexporter)
- `platform/otel/collector-config.yml`
