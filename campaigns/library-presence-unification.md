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

`2026-05-17`: **Phases 1 + 2 shipped in v0.63.0.** Phases 3–8
remain.

* Phase 1 — `Library.FilePresence` schema, migration
  `20260517100000_create_file_presences.exs`, and context API
  (`stamp/2`, `stamp_many/3`, `list_paths_for_watch_dir/1`,
  `list_stale/1`, `delete_paths/1`) live. Library boundary
  exports `FilePresence`. ADR-045 written.
* Phase 2 — Watcher dual-writes to both `Watcher.FilePresence`
  and `Library.FilePresence`; scan-dedup reads from
  `Library.FilePresence`. Backfill data migration
  `20260517100100_backfill_file_presences.exs` ran with an
  `INNER JOIN library_watched_files` filter — orphan
  `:present` KnownFile rows are intentionally excluded so
  the next watcher scan re-detects them fresh. That heals
  the original orphan-stuck-pipeline bug on upgrade (verified
  in this user's production: 206 WatchedFiles + 295-row
  ingest queue active after upgrade).
* Phases 3–8 — schema FK, read-site flip, DiscoveryProducer
  ETS dedup, AbsenceSweeper port, drop `watcher_files`,
  verification. See *Next steps* below.

## Decisions made

* `2026-05-17` — Library owns file presence; Watcher becomes
  a thin observer. Presence lives on a new
  `Library.FilePresence` schema, WatchedFile/ExtraFile FK to
  it, AbsencePolicy moves to `Library.AbsenceSweeper`,
  pipeline dedup moves to `DiscoveryProducer` ETS.
  ([ADR-045](../decisions/architecture/2026-05-17-045-file-presence-ownership.md))

## Next steps

Per the eight-phase plan in [ADR-045][1]. Each phase ships
green and is committable on its own; don't straddle. Phases 1
and 2 are ✅ done (see Status); resume at Phase 3.

1. ✅ **Phase 1.** Introduce `Library.FilePresence` schema +
   migration + context API. Non-breaking; no callers yet.
   Tests for the context.
2. ✅ **Phase 2.** Watcher writes through `Library.FilePresence`
   (dual-write with KnownFile). Backfill migration from
   `watcher_files`. Watcher's scan-dedup reads from
   FilePresence.
3. **Phase 3** *(next)***.** Add `file_presence_id` FK to WatchedFile and
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
* Sibling campaigns:
  * [`desktop-rearchitecture.md`](desktop-rearchitecture.md) —
    this campaign's three-pillar alignment is captured under
    its Workstream-A and pillar audit. Cross-referenced as a
    sibling pillar-cleanup arc.
  * [`library-schema-v2.md`](library-schema-v2.md) — Pillar-1
    schema redesign that landed alongside; the FK from
    `WatchedFile` / `ExtraFile` in Phase 3 of this campaign
    attaches to the PlayableItem-driven leaf model
    library-schema-v2 established.
* Phase-7 drop migration auto-heals any future installs that
  enter the same orphan-stuck-pipeline state this user hit on
  2026-05-17 (resolved operationally by v0.63.0's backfill
  intentionally skipping orphans).

[1]: ../decisions/architecture/2026-05-17-045-file-presence-ownership.md
