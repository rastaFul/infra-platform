# Resilience Patterns

## Timeout

- Every external call MUST have a timeout
- Default: 5s for HTTP, 10s for database, 30s for batch operations
- Timeout produces a clear error, not a hang

## Retry

- Retry only on transient errors (5xx, network timeout, connection refused)
- Never retry on 4xx (client error)
- Exponential backoff: 1s, 2s, 4s (max 3 retries)
- Add jitter to prevent thundering herd
- Always log retry attempts

## Circuit Breaker

States: CLOSED → OPEN → HALF-OPEN

| Parameter | Default |
|-----------|---------|
| Failure threshold | 5 failures in 60s |
| Open duration | 30s |
| Half-open max requests | 3 |

When OPEN: fail fast, don't call the service. Return cached/default value or error.

## Queue Patterns (SQS/RabbitMQ/etc.)

- Always use dead-letter queue (DLQ)
- Max receive count: 3 before DLQ
- Visibility timeout > processing time
- Idempotent consumers (same message processed twice = same result)

## Graceful Shutdown

```
SIGTERM received →
  1. Stop accepting new requests
  2. Finish in-flight requests (timeout: 30s)
  3. Close database connections
  4. Log shutdown
  5. Exit 0
```

## Health Checks

- Liveness: "is the process alive?" (simple ping)
- Readiness: "can it serve traffic?" (check dependencies)
- Startup: "has it finished initializing?" (for slow starts)
