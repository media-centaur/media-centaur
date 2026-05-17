---
status: in-progress
started: 2026-05-17
last_updated: 2026-05-17
---
# Library presence unification

## Goal

Eliminate the parallel-state-machine class of bug between
`Watcher.KnownFile` and `Library.WatchedFile`. Move the
durable record of "we've observed this path" into Library as
a first-class schema (`Library.FilePresence`), give
WatchedFile/ExtraFile a FK to it, and reduce the Watcher
context to a thin filesystem-observer adapter with no
persistent state.

This makes the orphan-stuck-pipeline class of bug (currently
biting prod — 696 KnownFile rows with no matching
WatchedFile, library idle) structurally impossible after the
campaign lands.

## Status

`2026-05-17`: Phase 0 in progress. ADR-045 written. Campaign
spec authored. Schema + migration not yet started.

## Decisions made

* `2026-05-17` — Library owns file presence; Watcher becomes
  a thin observer. Presence lives on a new
  `Library.FilePresence` schema, WatchedFile/ExtraFile FK to
  it, AbsencePolicy moves to `Library.AbsenceSweeper`,
  pipeline dedup moves to `DiscoveryProducer` ETS.
  ([ADR-045](../decisions/architecture/2026-05-17-045-file-presence-ownership.md))

## Next steps

Per the eight-phase plan in [ADR-045][1]. Each phase ships
green and is committable on its own; don't straddle.

1. **Phase 1.** Introduce `Library.FilePresence` schema +
   migration + context API. Non-breaking; no callers yet.
   Tests for the context.
2. **Phase 2.** Watcher writes through `Library.FilePresence`
   (dual-write with KnownFile). Backfill migration from
   `watcher_files`. Watcher's scan-dedup reads from
   FilePresence.
3. **Phase 3.** Add `file_presence_id` FK to WatchedFile and
   ExtraFile. Backfill from `file_path`. Tighten to non-null
   after backfill.
4. **Phase 4.** Read-site flip: every Library join on
   `watcher_files` switches to `library_file_presences`. One
   commit per join site so bisect is precise. Tests updated
   per site.
5. **Phase 5.** DiscoveryProducer ETS dedup; Parse stage gets
   a defensive `WatchedFile` / `ExtraFile` idempotency check.
   KnownFile becomes a dead write.
6. **Phase 6.** New `Library.AbsenceSweeper` GenServer.
   Delete `Watcher.AbsencePolicy`. Topic + payload contract
   for `{:files_removed, paths}` preserved verbatim.
7. **Phase 7.** Stop dual-writes. Drop `watcher_files` table
   with inline reconcile-orphan pass (any `:present`
   KnownFile row without matching FilePresence gets a fresh
   FilePresence so the next scan re-detects). Delete
   `Watcher.KnownFile`, `Watcher.FilePresence`,
   `Watcher.AbsencePolicy` modules.
8. **Phase 8.** Verification: full precommit, real-library
   smoke, in-place upgrade smoke from the current production
   state. Update `docs/architecture.md` and `docs/watcher.md`
   ownership tables.

## Completion criteria

* `Watcher.KnownFile`, `Watcher.FilePresence`,
  `Watcher.AbsencePolicy` modules deleted; `watcher_files`
  table dropped.
* `Library.FilePresence` is the sole durable presence record;
  all reads and writes pass through it.
* WatchedFile and ExtraFile have non-null
  `file_presence_id`; cascade-delete from FilePresence works
  end-to-end.
* `mix boundaries` reports zero cross-context joins on
  `watcher_files` (the table no longer exists; any leftover
  reference is a compile error).
* Real-library smoke: setup tour → ingest → library
  populates → remove a file → AbsenceSweeper TTL → entity
  deleted. All on a clean install.
* In-place upgrade smoke: take this user's exact current
  state (696 orphan KnownFile rows + empty library) and apply
  the post-Phase-7 build. Library populates after the
  reconcile-on-drop migration runs.
* `docs/architecture.md` ownership table reflects "Library
  owns file presence; Watcher is filesystem-observer adapter".

## Pointers

* [ADR-045 — File-presence ownership][1]
* [ADR-029 — Data decoupling](../decisions/architecture/2026-03-26-029-data-decoupling.md)
* [ADR-040 — Data migrations](../decisions/architecture/2026-05-09-040-data-migrations.md)
* [ADR-042 — Multi-session campaigns](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
* Bridge: this user's current install has 696 orphan
  `:present` `KnownFile` rows blocking ingest. This is an
  operational issue resolved by a manual delete + rescan,
  separate from the campaign. Phase 7's drop migration is
  the durable in-place upgrade for the same state.

[1]: ../decisions/architecture/2026-05-17-045-file-presence-ownership.md
