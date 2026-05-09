---
status: accepted
date: 2026-05-09
---
# Data migrations — a parallel migrator for one-shot row backfills

## Context and Problem Statement

Every shipping release introduces the chance that existing rows need fixing up to fit new code: a column added in one version is `NULL` for old rows; an aggregate introduced later (e.g. [Pursuits, ADR-039](2026-05-07-039-acquisition-pursuits.md)) leaves earlier `Grab` rows orphaned without a `pursuit_id`; an enum value changes spelling. So far we've handled these by inlining `execute("UPDATE …")` inside an ordinary schema migration (see `20260503180000_heal_grabs_tmdb_type_tv_series.exs`). That works for tiny, surgical fixes that genuinely belong with a schema change. It breaks down for anything else:

1. **Schema migrations want to be fast and atomic.** Long row-level backfills don't fit. The boot sequence runs them with the symlink unflipped and the user staring at a stalled installer.
2. **Schema and data have different dependency directions.** A schema migration must run *before* the new code starts (the column has to exist). A data backfill often wants to run *after* the new code is up — using the new aggregate's invariants, the new validation rules, possibly even Oban jobs the new release brings online.
3. **Folding both into one stream punishes you on rollback.** A schema migration that also rewrites a million rows can't be cleanly reversed. Splitting the concerns lets the schema half stay reversible.
4. **Per-deploy ad-hoc scripts (`mc-rpc 'expr'`) are unobservable and easy to forget.** A new dev install or a re-imaged production node never gets the fix-up. There's no record that the script ran.

We need a sanctioned mechanism: deploys auto-apply pending row-level fix-ups, each one runs exactly once per database, and the audit trail is on disk.

## Decision Outcome

Chosen option: **a parallel `Ecto.Migrator` stream rooted at `priv/repo/data_migrations/`, tracked in its own `data_migrations` table, run after schema migrations on every deploy.**

Small, surgical row-fixups that genuinely belong with a schema change (e.g. `priv/repo/migrations/20260503180000_heal_grabs_tmdb_type_tv_series.exs`, which heals an enum spelling drift in the same migration that makes the enum canonical) remain inlined in their schema migration. The new mechanism is for everything else — backfills that ride on top of the new schema, that are too long for the schema migration's atomicity expectations, or that need to call domain logic (via `oban_jobs` enqueue, per the rules below) to do their work.

### File layout

```
priv/repo/
  migrations/          # schema migrations — schema_migrations table
  data_migrations/     # data migrations — data_migrations table
    20260509120000_backfill_orphaned_pursuits.exs
```

Each data migration is an ordinary `Ecto.Migration` module. It is loaded by `Ecto.Migrator.run/4` against the second path with `migration_source: "data_migrations"`, so completion tracking is exactly-once and survives crashes the same way schema migrations do.

### Authoring rules

- **Use raw SQL** (`repo().query!/2` or the `execute/1` macro). Do not alias live schema or context modules. A migration is a snapshot — domain code rots out from under it, validation rules tighten, fields get renamed. Live code in a migration body breaks when re-played on a fresh install months later. Raw SQL pinned to column names is the safer default. The one allowance is the migration file's own private functions (extracted purely for testability) — the migration file itself is treated as immutable, so the helper module's surface is also frozen.
- **Idempotent at the row level.** `Ecto.Migrator` only marks a migration done after `up/0` returns successfully — if the body crashes halfway, the entire body re-runs. Use WHERE clauses that exclude already-processed rows (e.g. `WHERE pursuit_id IS NULL`). This is a stronger contract than schema migrations need.
- **Append-only.** Never edit a shipped data migration. Fix forward with a new file. Same rule that already governs `priv/repo/migrations/`, formalised here too.
- **Sync only.** The runner runs everything inline. For backfills that genuinely need to be async — long walks, external API calls, rate-limited work — the migration **enqueues an Oban job** (an `INSERT` into `oban_jobs`, raw SQL, snapshot-style) rather than performing the work itself. The running app picks up those jobs after boot. We deliberately did not build a mode-dispatcher: a single-mode runner with "delegate to Oban via insert" is simpler and covers the same ground.
- **`down/0` returns `:ok`.** Data migrations are forward-only; rollback is a new corrective migration.

### Boot integration

`MediaCentarr.Release.migrate_data/0` (alongside the existing `migrate/0`) is invoked by the installer immediately after schema migrations and before the symlink flip:

```sh
"$target/bin/media_centarr" eval "MediaCentarr.Release.migrate()"
"$target/bin/media_centarr" eval "MediaCentarr.Release.migrate_data()"
```

If either step fails, the symlink does not flip — the running service continues on the previous release. In-app updates re-exec the new installer, so they traverse the same path; there is no second wiring.

For dev parity, `mix ecto.migrate_data` is added to the `ecto.setup` alias chain so a fresh checkout converges to the same state. The test alias intentionally omits it: tests validate data migrations by direct calls into the migration's exported helper, not by running the migrator inside a sandboxed test transaction.

### Tracking table

The `data_migrations` table has the same shape Ecto creates for `schema_migrations` (a `version` bigint and inserted_at timestamp) — created lazily on first migrator run via `ensure_migrations_table?: true` (the default). No separate migration introduces it; the migrator's normal bookkeeping handles the lifecycle.

### Consequences

* Good, because **schema concerns and data concerns no longer share a stream.** Schema migrations stay fast and reversible; backfills get the runway they need without blocking the symlink flip beyond their own duration.
* Good, because **every deploy auto-applies pending fixups** — no `mc-rpc` operator step, no possibility of a re-imaged node missing a backfill that was a one-off script on the old node.
* Good, because **the snapshot rule (raw SQL, no live aliases, append-only) survives refactors.** Replaying history on a fresh install in 2027 does not break because we renamed a context module in 2026.
* Bad, because **raw SQL means domain validation isn't applied at backfill time.** A backfill could insert a row that violates a changeset rule the live code would have rejected. Mitigated by the row-level idempotency contract and by reviewing each migration as its own gated piece of work.
* Bad, because **a long sync-mode backfill blocks installer completion.** For now this is acceptable — the project's scale fits sync mode and the Oban-job-enqueue escape hatch covers the cases that don't. If a multi-hour backfill ever genuinely needs to run on a deploy, we'll revisit then; designing for it now would be premature.
* Bad, because **`Ecto.Migrator` re-runs the whole `up/0` on partial failure**, so authors must carry the row-level idempotency burden personally. Documented prominently in `MediaCentarr.DataMigrations` and enforced by review.
