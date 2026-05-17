---
status: accepted
date: 2026-05-17
---
# File-presence ownership belongs to Library; Watcher is a thin observer

## Context and Problem Statement

The watcher and library track overlapping concepts in two
independent persistent tables:

* `MediaCentarr.Watcher.KnownFile` (table `watcher_files`) — "the
  scanner has seen this path; here's its `:present | :absent`
  state and absent-since clock."
* `MediaCentarr.Library.WatchedFile` (table `library_watched_files`)
  — "this disk file IS this library entity's file."

Both ultimately answer "what files do we know about" from
different processes' viewpoints. The seam between them is
problematic in two concrete ways:

1. **The tables silently desync.** Pipeline failures (TMDB 401
   for every discovery), destructive migrations (Library Schema
   v2), BEAM crashes mid-pipeline — any of these can leave a
   `KnownFile :present` row with no matching `WatchedFile`. The
   scanner's diff (`disk - KnownFile`) reports `0 new`, the
   pipeline sits idle, the library stays empty. We've seen this
   in production this week (696 orphan rows). The reset path the
   user took to recover was destructive (wipe the data dir).

2. **Library code reaches across the boundary.** Eight query
   sites in `Library` and its sub-modules join `watcher_files`
   directly to answer "is this entity's file present?" That's an
   ADR-029 (data-decoupling) violation today, accreting more
   join sites as Library features grow.

Symptom-cover candidates considered and rejected:

* **(A)** Boot-time orphan reconciliation: delete `:present`
  KnownFile rows with no matching WatchedFile. ~30 lines, heals
  on every boot. Rejected as the *primary* fix because the
  two-table-must-stay-in-sync invariant remains; future bugs
  can still create orphans between boots.
* **(B-overload)** Add a `last_seen_at` column to `WatchedFile`
  and derive presence from it. Rejected because WatchedFile is
  meant to be the *join* between a confirmed disk file and a
  library entity — overloading it to also represent "file seen
  but not yet matched" makes WatchedFile a dual-purpose row
  whose meaning depends on a sentinel column.

## Decision Outcome

Chosen option: **Library owns file presence as a first-class
schema; Watcher becomes a thin filesystem observer with no
durable state.**

Concretely:

* New schema **`MediaCentarr.Library.FilePresence`** (table
  `library_file_presences`). One row per path observed in any
  watch dir. Fields: `id (UUID)`, `file_path :string UNIQUE`,
  `watch_dir :string`, `last_seen_at :utc_datetime_usec`. Indexed
  on `(watch_dir, last_seen_at)` for absence sweeps.
* **`WatchedFile` and `ExtraFile` reference** FilePresence via a
  plain `file_presence_id` UUID column. Library entities can only
  exist for files we've actually observed (enforced at the
  changeset layer via `validate_required(:file_presence_id)` and
  by routing all writes through `Library.link_file/1` /
  `create_extra_file/1`, which auto-stamp a presence row).
  *Originally a DB-level FK with `on_delete: :delete_all`; dropped
  per [ADR-046](2026-05-17-046-app-owned-cascading-deletes.md) —
  cascading deletes are an application concern.*
* TTL-driven absence detection moves to a new
  **`Library.AbsenceSweeper`** GenServer that sweeps stale
  FilePresence rows and broadcasts the existing
  `{:files_removed, paths}` contract on `library_file_events()`.
  `FileEventHandler` consumes it unchanged.
* Pipeline dedup leaves the database. **`DiscoveryProducer`**
  gets an ETS-backed in-flight set so duplicate dispatches
  (e.g. two scans 100ms apart) collapse without depending on a
  DB upsert side-effect. The Parse stage adds a defensive
  `WatchedFile` / `ExtraFile` lookup as a second idempotency
  check.
* **Watcher.KnownFile, Watcher.FilePresence, Watcher.AbsencePolicy
  are deleted.** Watcher keeps `Watcher.MountStatus` (drive-mount
  detection is genuinely a watcher concern) and the per-dir
  filesystem-event server processes. It owns ZERO persistent
  state after the campaign.

### Consequences

* **Good.** The orphan-stuck-pipeline class becomes
  structurally impossible. No WatchedFile / ExtraFile can exist
  without its FilePresence, and the only way to "be seen"
  without a downstream entity is to be sitting in the pipeline
  between detection and match — a window that's bounded by the
  Parse stage's idempotency check.
* **Good.** Eight Library cross-context joins on `watcher_files`
  become in-context joins on `library.file_presences`. Library's
  Boundary surface shrinks; the ADR-029 violation goes away.
* **Good.** File presence generalises cleanly to any future
  "file" schema (subtitle sidecars, etc.) — they FK to a single
  presence record instead of each coordinating with the watcher.
* **Good.** Watcher's job description becomes much clearer:
  observe the filesystem, push events to Library, own the mount
  state machine. No durable state to test, migrate, or
  reconcile.
* **Bad.** The campaign is multi-session (8 phases). Phase 4
  (read-site flip) is the highest-risk slice because the
  presence join sites encode product behavior (hoist rules,
  browse filters). Each Library file's switch lands as its own
  commit so bisect is precise if a browse regresses.
* **Bad.** Removes a TTL-state-machine semantics surface
  (`:present | :absent | absent_since`) and replaces it with a
  single timestamp + sweep. Power expressed by the state
  machine — like "this file is *known to be* absent, distinct
  from never seen" — collapses into "`last_seen_at` is N
  seconds old". For now that's fine; the rest of the app only
  cares about the practical question "is it currently present?",
  which `last_seen_at > ago(ttl)` answers cleanly.
* **Bad.** Existing installs need a migration that backfills
  FilePresence from KnownFile, then drops `watcher_files` in
  the final phase. The drop migration includes a reconcile-
  orphan pass so this user's 696 orphan rows auto-heal on
  upgrade.

## Pointers

* Campaign: [`library-presence-unification`](../../campaigns/library-presence-unification.md)
* Affected boundaries: [ADR-029 data-decoupling](2026-03-26-029-data-decoupling.md)
* Schema-migration safety: [ADR-040 data-migrations](2026-05-09-040-data-migrations.md)
