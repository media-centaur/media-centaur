---
status: accepted
date: 2026-02-20
---
# SQLite via AshSqlite

## Context and Problem Statement

The media manager is a single-user desktop application. It needs persistent storage for entities, watched files, images, seasons, episodes, and settings. The database must survive external drive disconnects (media files live on removable storage, but the database should not).

## Considered Options

* SQLite on the system drive via AshSqlite
* PostgreSQL via AshPostgres
* Flat JSON files on disk

## Decision Outcome

Chosen option: "SQLite on the system drive via AshSqlite", because SQLite is zero-configuration, embeds directly in the application, and stores everything in a single file on the system drive. This means the database survives external drive disconnects — media files may become temporarily unavailable, but entity metadata and watch progress are never lost.

### Consequences

* Good, because zero external service dependencies — no database server to install or manage
* Good, because the database file lives on the system drive, decoupled from media storage mounts
* Good, because AshSqlite integrates with Ash resource definitions and auto-generates migrations
* Bad, because SQLite has limited concurrent write support — acceptable for a single-user app, but would not scale to multi-user
* Bad, because some Ash features (atomic validations like `attribute_in`/`attribute_equals`) cannot be expressed as atomic SQL in SQLite, requiring `require_atomic? false` and `strategy: :stream` for bulk operations on those actions
