# Error Handling

## Principles

- Every error has a type, message, and context
- Never throw raw strings
- Never do empty catch blocks
- Centralized error middleware at the interface layer
- Domain errors are distinct from infrastructure errors

## Error Hierarchy

```
BaseError (abstract)
├── DomainError (business rule violations)
│   ├── ValidationError
│   ├── NotFoundError
│   └── ConflictError
├── InfrastructureError (external system failures)
│   ├── DatabaseError
│   ├── ExternalServiceError
│   └── TimeoutError
└── ApplicationError (use case failures)
    ├── UnauthorizedError
    └── ForbiddenError
```

## HTTP Mapping

| Error Type | HTTP Status |
|-----------|-------------|
| ValidationError | 400 |
| UnauthorizedError | 401 |
| ForbiddenError | 403 |
| NotFoundError | 404 |
| ConflictError | 409 |
| InfrastructureError | 502/503 |
| Unknown | 500 |

## Rules

- Log the full error (stack, context) server-side
- Return sanitized error to client (no stack traces, no internal details)
- Include correlation ID in error responses
- Use early return pattern to reduce nesting
