---
status: accepted
date: 2026-03-07
---
# Regression tests are append-only

## Context and Problem Statement

The parser and Broadway pipeline process files silently in the background. Bugs in either produce invisible data corruption — a misparsed filename, a dropped entity, a malformed push to the frontend. Both subsystems have accumulated test suites where each test represents a specific real-world scenario that has caused or could cause silent failure. When code changes cause these tests to fail, there is a temptation to delete or weaken the failing test rather than fix the underlying code.

## Decision Outcome

Chosen option: "Regression tests may only be added, never removed or weakened", because each test represents a real scenario and removing it re-opens the door to that failure.

1. **Parser tests use real file paths observed in the wild** — never synthetic/invented paths. Each distinct filename convention gets its own test case. If a parser change causes an existing test to fail, fix the parser.
2. **Pipeline tests represent real processing scenarios.** Each test guards against a specific failure mode — silent data corruption, dropped files, malformed entities. If a pipeline change causes a test to fail, fix the pipeline.
3. **Test assertions must not be weakened** (e.g., changing an exact match to a substring match, loosening numeric bounds) to accommodate a code change.

Complements [ADR-012](2026-02-27-012-engineering-standards.md), which establishes the test-first discipline.

### Consequences

* Good, because the test suite is a monotonically growing record of real failure modes
* Good, because developers are forced to maintain backward compatibility or consciously handle migration
* Bad, because the test suite grows indefinitely and may slow down over time
