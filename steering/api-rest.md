# REST API Conventions

## URL Structure

- Resources are nouns, plural: `/users`, `/orders`
- Nested resources: `/users/:id/orders`
- Actions (when needed): `/orders/:id/cancel`
- Always lowercase, kebab-case for multi-word: `/order-items`

## HTTP Methods

| Method | Usage | Idempotent |
|--------|-------|-----------|
| GET | Read | Yes |
| POST | Create | No |
| PUT | Full replace | Yes |
| PATCH | Partial update | Yes |
| DELETE | Remove | Yes |

## Status Codes

- 200: Success with body
- 201: Created (include Location header)
- 204: Success, no body
- 400: Bad request (validation)
- 401: Unauthenticated
- 403: Unauthorized
- 404: Not found
- 409: Conflict
- 422: Unprocessable entity
- 500: Internal error

## Pagination

```json
{
  "data": [...],
  "pagination": {
    "page": 1,
    "pageSize": 20,
    "total": 150,
    "totalPages": 8
  }
}
```

## Error Response

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Human-readable message",
    "details": [{"field": "email", "message": "Invalid format"}],
    "correlationId": "uuid"
  }
}
```

## Health Check

- `GET /health` → 200 with `{"status": "ok", "version": "1.0.0"}`
