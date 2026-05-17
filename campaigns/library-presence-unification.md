---
status: in-progress
started: 2026-05-17
last_updated: 2026-05-17
phases_done: [1, 2, 3]
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

`2026-05-17`: **Phases 1 + 2 shipped in v0.63.0; Phase 3
landed on `main`.** Phases 4–8 remain.

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
* Phase 3 — `library_watched_files` and `library_extra_files`
  gain a `file_presence_id` FK column with
  `on_delete: :delete_all` (schema migration
  `20260517110000_add_file_presence_id_to_library_files.exs`).
  `Library.link_file/1` and `Library.create_extra_file/1` now
  stamp `Library.FilePresence` for `(file_path, watch_dir)`
  before insert/update and inject the id; both changesets
  cast and `validate_required(:file_presence_id)`. Data
  migration `20260517110200_backfill_file_presence_ids.exs`
  seeds presence rows + populates the FK for any pre-existing
  leaf rows. Cascade-delete is verified end-to-end in
  `file_presence_test.exs`.
  **Deferred:** the campaign's "tighten to non-null" step
  cannot land in the same release as the backfill because
  `MediaCentarr.Release` runs *all* schema migrations before
  *any* data migration (see `lib/media_centarr/release.ex`
  comments), so a NOT-NULL schema migration paired with the
  Phase-3 backfill would fail at boot. Non-null is enforced
  at the changeset layer today; the DB-level constraint
  ships as a one-line follow-up migration in a later release
  once every install has run the backfill (tracked as the
  first sub-task of Phase 7).
* Phases 4–8 — read-site flip, DiscoveryProducer ETS dedup,
  AbsenceSweeper port, drop `watcher_files`, verification.
  See *Next steps* below.

## Decisions made

* `2026-05-17` — Library owns file presence; Watcher becomes
  a thin observer. Presence lives on a new
  `Library.FilePresence` schema, WatchedFile/ExtraFile FK to
  it, AbsencePolicy moves to `Library.AbsenceSweeper`,
  pipeline dedup moves to `DiscoveryProducer` ETS.
  ([ADR-045](../decisions/architecture/2026-05-17-045-file-presence-ownership.md))

## Next steps

Per the eight-phase plan in [ADR-045][1]. Each phase ships
green and is committable on its own; don't straddle. Phases
1–3 are ✅ done (see Status); resume at Phase 4.

1. ✅ **Phase 1.** Introduce `Library.FilePresence` schema +
   migration + context API. Non-breaking; no callers yet.
   Tests for the context.
2. ✅ **Phase 2.** Watcher writes through `Library.FilePresence`
   (dual-write with KnownFile). Backfill migration from
   `watcher_files`. Watcher's scan-dedup reads from
   FilePresence.
3. ✅ **Phase 3.** Added `file_presence_id` FK to WatchedFile
   and ExtraFile (`on_delete: :delete_all`). `Library.link_file/1`
   and `create_extra_file/1` stamp presence + inject id;
   changesets `validate_required(:file_presence_id)`.
   Backfill data migration runs against pre-existing rows.
   DB-level NOT-NULL is deferred to a follow-up migration in
   the release *after* the backfill has run everywhere — see
   the Phase-7 first sub-task below.
4. **Phase 4** *(next)***.** Read-site flip: every Library join on
   `watcher_files` switches to `library_file_presences`. One
   commit per join site so bisect is precise. Tests updated
   per site.
5. **Phase 5.** DiscoveryProducer ETS dedup; Parse stage gets
   a defensive `WatchedFile` / `ExtraFile` idempotency check.
   KnownFile becomes a dead write.
6. **Phase 6.** New `Library.AbsenceSweeper` GenServer.
   Delete `Watcher.AbsencePolicy`. Topic + payload contract
   for `{:files_removed, paths}` preserved verbatim.
7. **Phase 7.** Tighten `file_presence_id` to NOT NULL on
   both `library_watched_files` and `library_extra_files`
   (the Phase-3 deferral — safe to ship once every install
   has booted the Phase-3 backfill). Then stop dual-writes.
   Drop `watcher_files` table with inline reconcile-orphan
   pass (any `:present` KnownFile row without matching
   FilePresence gets a fresh FilePresence so the next scan
   re-detects). Delete `Watcher.KnownFile`,
   `Watcher.FilePresence`, `Watcher.AbsencePolicy` modules.
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
