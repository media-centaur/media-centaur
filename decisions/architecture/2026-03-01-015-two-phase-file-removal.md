---
status: accepted
date: 2026-03-01
---
# Two-phase file removal: immediate cleanup for deletions, TTL for unavailability

## Context and Problem Statement

When media files are deleted from watch directories or drives are disconnected, the application has no mechanism to detect or respond. Stale records remain in the database, the UI shows unplayable entities, and playback fails silently. The only recovery is the destructive "Clear Database" admin operation.

File removal has two distinct causes with different semantics: (1) the user intentionally deleted files (permanent — clean up immediately), and (2) a drive was disconnected or unmounted (possibly temporary — retain records for a grace period). A single strategy cannot serve both cases well.

## Considered Options

* Single-phase: mark all missing files as absent, TTL governs all cleanup
* Two-phase: immediate cleanup for confirmed deletions, TTL-deferred cleanup for unavailability
* Periodic reconciliation only (no real-time detection)

## Decision Outcome

Chosen option: "two-phase file removal", because it gives immediate feedback for intentional deletions (the common case) while protecting against premature cleanup when drives are temporarily disconnected.

**Phase 1 — Confirmed deletion (immediate):** inotify `:deleted` events are debounced (~3 seconds) and trigger immediate cleanup of all related records (WatchedFile, child Episode/Movie/Extra, orphaned parent entities, Image records, and cached image files on disk). No intermediate state is needed.

**Phase 2 — Unavailability (TTL-deferred):** When a filesystem is unmounted or the Watcher cannot access its directory, all WatchedFiles for that watch directory are marked `:absent` with a timestamp. These entities are removed from the frontend but retained in the database. A periodic check (daily) purges records whose `absent_since` exceeds a configurable TTL. When a drive returns, a scan restores absent files to `:complete`.

### Consequences

* Good, because intentional file deletions are reflected in the UI within seconds — no phantom entries
* Good, because temporary drive disconnections don't destroy metadata, watch progress, or cached images
* Good, because the TTL is configurable per deployment (USB-heavy setups may want shorter TTL, NAS setups longer)
* Good, because the two paths share the same cleanup cascade logic — only the trigger differs
* Bad, because this adds a new WatchedFile state (`:absent`) and a periodic process, increasing system complexity
* Bad, because the debounce window means there is a brief delay (~3s) between file deletion and UI update
