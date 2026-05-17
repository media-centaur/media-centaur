---
status: accepted
date: 2026-05-17
---
# Cascading deletes are an application concern, not a database concern

## Context and Problem Statement

The library-presence-unification campaign (ADR-045) added a foreign
key from `library_watched_files` and `library_extra_files` to
`library_file_presences` with `on_delete: :delete_all`. The intent
was structural: a library entity can only exist for a file we've
actually observed.

Closing out the campaign exposed the cost of that decision on this
project's stack:

1. **SQLite has no `ALTER TABLE ... ALTER COLUMN`.** Tightening
   `file_presence_id` to `NOT NULL` (the Phase-3 deferral) required
   a 12-step table rebuild. So did *dropping* the FK constraint
   later if we ever wanted to. Any constraint mistake compounds.
2. **The cascade isn't actually exercised at runtime.** Walk the
   delete paths:
   - `Library.AbsenceSweeper.purge_expired/1` calls
     `FileEventHandler.cleanup_removed_files/1` synchronously
     *before* deleting `FilePresence` rows. By the time the FK
     fires, the dependent `WatchedFile` / `ExtraFile` rows are
     already gone — cascade is a no-op.
   - Inotify-driven deletions never delete `FilePresence` at all;
     `FileEventHandler` deletes the dependent rows directly.
   - Application writes go through `Library.link_file/1` /
     `create_extra_file/1`, both of which `validate_required` on
     `file_presence_id` at the changeset layer.
3. **Library-wipe-on-cascade-bug risk.** AbsenceSweeper's
   drive-availability gate (ADR-045's durability invariant) only
   protects what *it* deletes. A future code path or migration that
   deletes a `FilePresence` row outside that gate would silently
   cascade-delete every `WatchedFile` for that path. With no
   cascade, the same bug leaves orphan presence rows — visible and
   recoverable.
4. **Invisible coupling.** FKs encode the same coupling as Boundary
   deps but at the database layer, where it's harder to see and
   reason about during refactors.
5. **Per-connection `PRAGMA foreign_keys` default-off in SQLite.**
   Enforcement varies between dev `iex` and prod release
   connections unless every config path enables it consistently.

## Decision Outcome

Chosen option: **the application owns cascading deletes. The
database stores plain UUID references; no `on_delete:` clauses on
new schema additions, and existing ones are migrated off as their
surrounding code is touched.**

Concretely for the campaign close-out:

* The Phase-3 FK on `library_watched_files.file_presence_id` and
  `library_extra_files.file_presence_id` is dropped. The column
  remains as a plain UUID reference — useful as a lookup key from a
  WatchedFile to its presence row.
* The structural invariant ("no entity without a presence") is
  enforced exclusively at the changeset layer via
  `validate_required(:file_presence_id)` on
  `WatchedFile.link_file_changeset/1` and
  `ExtraFile.link_file_changeset/1`. Write paths
  (`Library.link_file/1` / `create_extra_file/1`) auto-stamp a
  `Library.FilePresence` row before insert, so the field is
  populated by construction.
* The cleanup-on-delete invariant ("when presence goes, the entity
  goes") is enforced explicitly by
  `Library.AbsenceSweeper.purge_expired/1`:
  `FileEventHandler.cleanup_removed_files/1` runs first (deletes
  `WatchedFile` / `ExtraFile` + the entity-cleanup cascade), then
  `FilePresence.delete_paths/1`. This is the same sequence the
  pre-drop code already used — the FK was never the active barrier.

### Migrating off SQLite's ALTER limitation

SQLite supports `RENAME COLUMN`, `ADD COLUMN`, and `DROP COLUMN`
individually. To drop an FK without rebuilding the entire table:

1. `ALTER TABLE … RENAME COLUMN file_presence_id TO file_presence_id_legacy`
2. `ALTER TABLE … ADD COLUMN file_presence_id BLOB`  (plain UUID, no FK)
3. `UPDATE … SET file_presence_id = file_presence_id_legacy`
4. `CREATE INDEX … ON …(file_presence_id)`
5. `ALTER TABLE … DROP COLUMN file_presence_id_legacy`  (drops the old FK + its index together)

This preserves all other indexes, all inbound FKs (e.g.
`subtitles_tracks.watched_file_id` references
`library_watched_files.id` — untouched), and avoids the 12-step
rebuild.

### Scope

* **In scope (this ADR):** the Phase-3 FKs on
  `library_watched_files.file_presence_id` and
  `library_extra_files.file_presence_id`. Dropped in
  the migration that ships this decision.
* **Going forward:** new schema additions follow this principle —
  no `on_delete:` clauses. Use `references(:other_table, type:
  :uuid)` (plain) and handle cleanup ordering in application code.
* **Grandfathered (in-scope for future work):** the other five
  cascade-delete FKs currently in the schema —
  `library_playable_items` → `library_watched_files`,
  `library_playable_items` → `library_watch_progress`,
  `library_extras` → `library_extra_files`,
  `library_watched_files` → `subtitle_tracks` (inbound from
  Subtitles), `release_tracking_items` → `release_tracking_*`.
  These move off the DB layer as their surrounding code gets
  touched. No bulk migration; no deadline.

### Consequences

* **Good.** SQLite `ALTER COLUMN` is no longer an architectural
  constraint on us. Adding / changing FK behaviour stops requiring
  table rebuilds.
* **Good.** A bug that deletes a presence row outside
  `AbsenceSweeper` leaves an orphan instead of vaporising library
  rows. Recovery becomes "scan and re-stamp" rather than "restore
  from backup".
* **Good.** Boundary coupling becomes the single source of truth
  for inter-context dependencies; the schema no longer encodes a
  parallel hidden graph.
* **Good.** Test fixtures stop depending on parent-row creation
  order — raw `Repo.insert` works for setting up edge cases.
* **Bad.** Loses the DB-level "can't insert orphan" guarantee. A
  bug in a writer (bypassing `Library.link_file/1` and inserting
  via raw SQL or a hand-rolled changeset) could leave a
  `WatchedFile` pointing at a non-existent presence row.
  Mitigation: writes go through one of two functions
  (`link_file/1` / `create_extra_file/1`) by construction; both
  auto-stamp the presence row.
* **Bad.** Tests that previously asserted "deleting a presence
  cascade-deletes the entity" now have to drive the cleanup
  explicitly (via `FileEventHandler.cleanup_removed_files/1` or
  `AbsenceSweeper.purge_expired/1`). Same end-state assertion,
  different setup.

## Pointers

* Campaign that triggered this decision:
  [`library-presence-unification`](../../campaigns/done/library-presence-unification.md)
* The owning ADR for file presence: [ADR-045](2026-05-17-045-file-presence-ownership.md) — amended in
  the same commit as this ADR to reflect the FK drop.
* Boundary-coupling principle (the analogous app-layer rule):
  [ADR-029](2026-03-26-029-data-decoupling.md).
