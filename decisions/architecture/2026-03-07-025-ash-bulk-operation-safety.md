---
status: accepted
date: 2026-03-07
---
# Ash bulk operation safety

## Context and Problem Statement

Ash bulk operations (`Ash.bulk_create`, `Ash.bulk_update`, `Ash.bulk_destroy`) silently discard errors by default. Callers receive a result struct but may not notice that some or all records failed. Additionally, AshSqlite cannot express certain validations (`attribute_in`, `attribute_equals`) as atomic SQL, so actions with these validations fail under the default `:atomic` bulk strategy with `NoMatchingBulkStrategy`.

## Decision Outcome

Chosen option: "Require explicit error handling and correct strategy selection for all bulk operations", because silent bulk failures are invisible and have stalled entire subsystems in this application.

1. **Always pass `return_errors?: true`** to `Ash.bulk_create/4`, `Ash.bulk_update/4`, and `Ash.bulk_destroy/3`.
2. **Always check `result.error_count`** before assuming success. Never treat `result.records || []` as safe without verifying zero errors.
3. **Non-atomic actions require `strategy: :stream`.** Actions with validations that AshSqlite cannot express as SQL must set `require_atomic? false` on the action definition, and the corresponding `bulk_*` call must pass `strategy: :stream`.

Complements [ADR-003](2026-02-20-003-ash-as-exclusive-data-interface.md), which establishes bulk APIs as the required approach for multi-record operations.

### Consequences

* Good, because bulk operation failures surface immediately rather than silently corrupting state
* Good, because non-atomic actions work correctly with bulk APIs via stream strategy
* Bad, because every bulk call site requires additional boilerplate for error checking
