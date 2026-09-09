# Testing Standards

## TDD — Red-Green-Refactor

```
1. RED    — Write test that fails (defines expected behavior)
2. GREEN  — Write minimum code to pass the test
3. REFACTOR — Clean without changing behavior (test still passes)
```

- NEVER write production code without a failing test first
- NEVER write test after code (that's "torturing test to pass")
- The test defines the contract — code implements it
- If test passes immediately without new code → test is wrong

## Test Structure — AAA

```
// Arrange — setup
const service = new UserService(mockRepo);

// Act — execute
const result = await service.create(validInput);

// Assert — verify
expect(result.id).toBeDefined();
```

## Coverage Targets

- Use cases / services: ≥80%
- Overall project: ≥60%
- New code: 100% (TDD guarantees this)

## What to Test

- **Unit tests**: Services, use cases, domain logic. Mock external deps.
- **Integration tests**: Handlers/controllers with real middleware. Mock only external services.
- **Never test**: Framework internals, getters/setters, trivial code.

## Naming

```
describe('UserService')
  describe('create')
    it('should create user with valid input')
    it('should throw ValidationError when email is invalid')
    it('should throw ConflictError when email already exists')
```

## Mocking

- Mock at the boundary (repository, external service)
- Never mock the thing you're testing
- Prefer dependency injection over module mocking
