---
status: accepted
date: 2026-02-20
---
# Ash Framework as exclusive data interface

## Context and Problem Statement

The application needs a data layer for entities, watched files, watch progress, images, identifiers, seasons, and episodes. Raw Ecto gives full control but requires hand-writing every changeset, query, and validation. The team needs to move fast while keeping data integrity guarantees strong.

## Decision Outcome

Chosen option: "Ash Framework as the only data interface", because Ash provides declarative resource definitions that serve as both documentation and implementation. Actions, validations, and relationships are defined once in the resource and automatically generate the correct database operations.

Key rules that follow from this decision:

- **No raw SQL, no `Ecto.Query`, no direct `Repo` calls.** All reads and writes go through Ash actions.
- **Bulk APIs for bulk operations.** Use `Ash.bulk_destroy/3`, `Ash.bulk_update/4`, `Ash.bulk_create/4` instead of looping single-record operations.
- **Ash-generated migrations only.** Run `mix ash_sqlite.generate_migrations` — never hand-write or edit Ecto migrations for Ash-managed tables.
- **Ash changes are intrinsic only.** Changes handle validation and transformation, never external integrations or cross-context calls.

### Consequences

* Good, because resource definitions are the single source of truth for schema, validations, and actions
* Good, because bulk APIs execute single queries instead of N+1 loops
* Good, because generated migrations stay in sync with resource definitions automatically
* Bad, because Ash has a learning curve — contributors must understand its action/changeset model
* Bad, because some operations that are trivial in raw Ecto (e.g., ad-hoc queries) require defining a new Ash action first
