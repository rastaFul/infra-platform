# Architecture — Clean Architecture

> This file is configurable. Replace with your preferred architecture pattern.

## Structure

```
src/
├── domain/          # Entities, value objects, pure business rules
├── application/     # Use cases, ports (interfaces), DTOs
├── infrastructure/  # Adapters (database, HTTP clients, queues, cache)
└── interface/       # Controllers, consumers, CLI handlers
```

## Rules

- **domain/** has ZERO external dependencies. Pure logic only.
- **application/** defines ports (interfaces). Never imports infrastructure.
- **infrastructure/** implements ports. Contains all external integrations.
- **interface/** is the entry point. Composes everything via DI.
- Dependency flow: interface → application → domain. Infrastructure implements application ports.

## Dependency Injection

- Compose at the entry point (main, app bootstrap)
- Use constructor injection
- Never import concrete implementations in application layer

## When to Break the Rules

- Prototypes and spikes: skip layers, but mark as tech debt
- Simple CRUD with no business logic: can flatten to 2 layers
- Always document the decision in DECISIONS.md
