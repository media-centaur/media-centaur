---
status: accepted
date: 2026-05-09
---
# Data migrations — a parallel migrator for one-shot row backfills

## Context and Problem Statement

Each release can leave existing rows needing a fix-up: a column that is `NULL` for old rows, an aggregate introduced later that leaves earlier rows unattached, an enum spelling that changed. Inlining `UPDATE` statements in schema migrations breaks down beyond tiny fixes — schema migrations want to be fast, atomic, and reversible, while a backfill often wants to run after the new code is up — and ad-hoc operator scripts are unobservable and never reach a re-imaged install.

## Decision Outcome

A second `Ecto.Migrator` stream, rooted at `priv/repo/data_migrations/` and tracked in its own `data_migrations` table, runs after schema migrations on every deploy.

1. `MediaCentaur.Release.migrate_data/0` runs after `migrate/0` on every deploy. `mix ecto.migrate_data` sits in the `ecto.setup` alias chain so a fresh checkout converges; the test alias omits it.
2. Data migrations are forward-only: `down/0` returns `:ok`, and a mistake is fixed by a new migration.
3. Authoring rules, owned by the `MediaCentaur.DataMigrations` moduledoc: raw SQL only, never live schema or context modules; idempotent at the row level, because a crash re-runs the whole body; no load-time side effects; append-only once shipped.
4. Long or external work is not performed inline: the migration enqueues an Oban job by inserting into `oban_jobs`, and the running application does the work.
5. A small, surgical row fix that genuinely belongs with a schema change may stay inline in that schema migration. MC0015 (`RowMutationInSchemaMigration`) fails bulk `UPDATE`/`DELETE` statements in `priv/repo/migrations/`, so anything larger lands in the data stream.

### Consequences

* Raw SQL bypasses changeset validation; a backfill can write what live code would reject. Each migration is reviewed as its own gated change.
* A long synchronous backfill blocks the deploy for its duration; the Oban escape hatch covers the cases that matter.
