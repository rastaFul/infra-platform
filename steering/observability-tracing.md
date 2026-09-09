# Observability — Distributed Tracing (OpenTelemetry)

## Standard

All services MUST be instrumented with OpenTelemetry for distributed tracing.

## Setup Pattern (Node.js)

Create a `tracing.cjs` (or `tracing.ts`) at project root:

```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318/v1/traces',
  }),
  instrumentations: [getNodeAutoInstrumentations()],
  serviceName: process.env.OTEL_SERVICE_NAME || 'my-service',
});

sdk.start();
process.on('SIGTERM', () => sdk.shutdown());
```

Start with: `node -r ./tracing.cjs src/index.js`

## What Gets Traced Automatically

With auto-instrumentation:
- HTTP incoming requests
- HTTP outgoing requests (axios, fetch, http)
- Database queries (pg, mysql, redis, mongodb)
- Message queues (amqplib, kafkajs)
- gRPC calls

## Custom Spans

Add custom spans for business-critical operations:

```javascript
const { trace } = require('@opentelemetry/api');
const tracer = trace.getTracer('my-service');

async function processOrder(order) {
  return tracer.startActiveSpan('process-order', async (span) => {
    span.setAttribute('order.id', order.id);
    span.setAttribute('order.total', order.total);
    try {
      const result = await doWork(order);
      span.setStatus({ code: SpanStatusCode.OK });
      return result;
    } catch (error) {
      span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
      throw error;
    } finally {
      span.end();
    }
  });
}
```

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| OTEL_SERVICE_NAME | Service identifier | my-service |
| OTEL_EXPORTER_OTLP_ENDPOINT | Collector endpoint | http://collector:4318 |
| OTEL_TRACES_SAMPLER | Sampling strategy | parentbased_traceidratio |
| OTEL_TRACES_SAMPLER_ARG | Sampling rate | 0.1 (10%) |

## Configuring Your Instrumentations

To add project-specific instrumentations or custom span patterns, create a `tracing-config.md` file in this directory. The agent will scan your codebase to discover existing patterns if no config is provided.
