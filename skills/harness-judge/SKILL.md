# Harness Judge — LLM-as-Judge

Evaluates agent output quality after each execution. The executing agent does NOT evaluate itself.

## Criteria

### Infra
| Criterion | Weight |
|-----------|--------|
| Correctness | 30% |
| Security | 25% |
| Idempotency | 15% |
| Blast radius | 15% |
| Documentation | 15% |

### Dev
| Criterion | Weight |
|-----------|--------|
| Correctness | 25% |
| Code quality | 25% |
| Test quality | 20% |
| TDD compliance | 15% |
| Documentation | 15% |

## Score

| Score | Classification |
|-------|---------------|
| 9-10 | Excellent |
| 7-8 | Good — minor steering adjustments |
| 5-6 | Regular — review specs or agent context |
| 3-4 | Poor — problem in steering or tools |
| 1-2 | Critical — stop and investigate |

## Where to Save

`.specs/metrics/YYYY-MM-DD-HHMMSS-[task-slug].judge.md`
