---
status: accepted
date: 2026-03-07
---
# Regression tests are append-only

## Context and Problem Statement

The parser and the pipeline run in the background, so a bug in either produces silent data corruption. Their test suites are a record of real scenarios that caused or could cause such a failure, and a failing test invites weakening it instead of fixing the code.

## Decision Outcome

Regression tests may be added, never removed or weakened.

1. Parser tests use real file paths observed in the wild, never invented ones; each distinct naming convention gets its own case. A parser change that breaks an existing case is a parser bug.
2. Pipeline tests each guard a specific failure mode. A pipeline change that breaks one is a pipeline bug.
3. Assertions are never loosened (exact match to substring, tighter to looser bound) to accommodate a code change.

The test-first workflow and the factories these tests use are in the `automated-testing` skill.

### Consequences

* The suites grow monotonically; [ADR-049](2026-05-22-049-testing-principles.md) keeps that growth inside a wall-time budget.
