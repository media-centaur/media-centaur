---
status: accepted
date: 2026-03-07
---
# Ash-driven migrations: resources as source of truth

## Context and Problem Statement

The application uses Ash Framework with AshSqlite. Migration files can drift from resource definitions if developers hand-write or manually edit them. This creates two sources of truth — the resource definition and the migration — leading to schema inconsistencies and merge conflicts. SQLite's limited `ALTER TABLE` support makes migration correctness especially important, as mistakes often require table recreation.

## Decision Outcome

Chosen option: "Generate all migrations from Ash resource definitions", because the resource is the single source of truth and generated migrations are a derived artifact.

1. **Never hand-write or edit Ecto migrations for Ash-managed tables.** Define attributes, identities, and relationships in the Ash resource, then run `mix ash_sqlite.generate_migrations --name <short_name>`.
2. **Custom SQL** (data backfills, deduplication, table recreation for SQLite constraints) goes in a **separate** manual migration file — never edit or replace an Ash-generated migration.
3. **Never use `Ecto.Migration` directly** to create, alter, or drop tables managed by Ash resources.

Complements [ADR-003](2026-02-20-003-ash-as-exclusive-data-interface.md), which establishes Ash as the only data interface.

### Consequences

* Good, because there is exactly one source of truth for schema shape — the resource definition
* Good, because migration conflicts are reduced since migrations are regenerated, not hand-edited
* Good, because custom SQL is isolated in clearly marked manual migrations
* Bad, because developers must express all schema changes through resource definitions rather than writing migrations directly
