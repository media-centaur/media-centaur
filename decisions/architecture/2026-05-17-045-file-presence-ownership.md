---
status: accepted
date: 2026-05-17
---
# File-presence ownership belongs to Library; Watcher is a thin observer

## Context and Problem Statement

Watcher and Library each kept a persistent table about known files, and the two desynced silently: a pipeline failure or crash could leave a watcher row with no library file, after which scans reported nothing new and the library stayed empty. Library also joined the watcher's table from eight query sites to answer "is this entity's file present", a cross-context coupling [ADR-029](2026-03-26-029-data-decoupling.md) forbids.

## Decision Outcome

1. **Library owns file presence.** `Library.FilePresence` (table `library_file_presences`) holds one row per path observed in any media directory, with `media_dir` and `last_seen_at`; "present" means `last_seen_at` is within the absence TTL.
2. **A library file cannot exist for an unobserved path.** `WatchedFile` and `ExtraFile` carry `file_presence_id`, required at the changeset layer and stamped by the Library write paths that link a file. It is a plain UUID column, not a database foreign key ([ADR-046](2026-05-17-046-app-owned-cascading-deletes.md)).
3. **Absence is a Library sweep.** `Library.AbsenceSweeper` purges rows past the TTL and broadcasts the existing `{:files_removed, paths}` contract, which the file-event handler consumes unchanged.
4. **Watcher owns no durable state.** It keeps mount detection (`Watcher.MountStatus`) and the per-directory filesystem event processes, and pushes events to Library.
5. **Pipeline dedup is in memory.** The discovery producer's in-flight set (`Pipeline.Discovery.InflightSet`) collapses duplicate dispatches; the parse stage's file lookup is the second idempotency check.

### Consequences

* The `:present | :absent | absent_since` state machine collapsed into one timestamp and a sweep; "known to be absent" is no longer distinguishable from "never seen".
* Presence rules encode product behaviour (hoist rules, browse filters), so a change to the TTL or the sweep is a behaviour change, not plumbing.
