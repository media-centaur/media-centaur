---
status: accepted
date: 2026-05-09
amended: 2026-11-14
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

## Amendment 2026-11-06 — a data fix never speaks for the person

A data fix must not reach friends. Raw SQL broadcasts nothing, which is the reason rule 3 keeps context modules out of a migration; the same holds for a repair run any other way. A fix that has to go through a context passes `nil` as the actor to every write that takes one, so nothing it does is shared (ADR-082). On 2026-11-05 a repair through the Watchlist context, made before that rule existed, published seven listings in one second.

## Amendment 2026-11-14 — one upgrade, run at every start

Rule 1 no longer describes the code. Schema and data migrations are one operation, `MediaCentaur.Release.migrate/0`: the snapshot when anything is pending, the schema migrations, then the data migrations. It runs at every application start, as `MediaCentaur.Application.DatabaseUpgrade`, directly before the Repo, so before any process that reads the database; the installer runs the same operation against the new release before it points `current` at it. `Release.migrate_data/0` and `mix ecto.migrate_data` are removed. On 2026-11-14 the dev service, whose unit ran only the schema migration before start, loaded watch-progress rows into memory that a data migration then rewrote, and showed the earlier values until it was restarted. The `Release` moduledoc holds the current contract.
