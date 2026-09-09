# Service Layers — Handler → Service → Repository

> This file is configurable. Replace with your preferred layering pattern.

## Pattern

```
Handler (interface layer)
  → receives request, validates input shape
  → calls Service

Service (application layer)
  → contains business logic
  → orchestrates repositories and external calls
  → returns result or throws domain error

Repository (infrastructure layer)
  → data access only
  → no business logic
  → returns domain entities
```

## Rules

- Handler NEVER contains business logic
- Service NEVER accesses database directly (uses repository)
- Repository NEVER calls other repositories
- No cross-layer logic (handler calling repository directly)
- Each layer has its own error types

## Naming

- Handlers: `CreateUserHandler`, `GetOrderHandler`
- Services: `UserService`, `OrderService`
- Repositories: `UserRepository`, `OrderRepository`
