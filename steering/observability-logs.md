# Observability — Structured Logs (OpenTelemetry)

## Standard

All services MUST emit structured logs following OpenTelemetry semantic conventions.

## Log Format

JSON structured logs with these base fields:

```json
{
  "timestamp": "2026-01-01T12:00:00.000Z",
  "level": "info",
  "message": "Request processed",
  "service.name": "my-service",
  "service.version": "1.0.0",
  "trace_id": "abc123",
  "span_id": "def456",
  "attributes": {}
}
```

## Log Levels

| Level | When to use |
|-------|-------------|
| error | Unrecoverable failure, requires attention |
| warn | Recoverable issue, degraded behavior |
| info | Significant business events (request start/end, state changes) |
| debug | Detailed diagnostic info (disabled in production) |

## What to Log

- Request received (method, path, correlation ID)
- Request completed (status, duration)
- Business events (order created, payment processed)
- External calls (service, duration, status)
- Errors (full context, stack trace)

## What NOT to Log

- Passwords, tokens, API keys
- PII (full phone numbers, emails, CPF/SSN)
- Message content (SMS body, email body)
- Credit card numbers
- Health check requests (too noisy)

## Logger Setup

Use a structured logger library (e.g., Pino for Node.js, Zap for Go, Logback for Java) configured to output JSON. Never use `console.log` or `print` in production code.

## Correlation

- Every request gets a correlation/trace ID
- Pass it through all internal calls
- Include in all log entries for that request
- OpenTelemetry trace context propagation handles this automatically

## Configuring Your Fields

To add project-specific required fields, create a `log-fields.md` file in this directory listing your mandatory fields. The agent will scan your codebase to discover existing patterns if no config is provided.
