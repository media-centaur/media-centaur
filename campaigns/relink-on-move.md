---
status: planning
started: 2026-05-30
last_updated: 2026-05-30
---
# Relink media on move

## Goal

Make "I moved my media to a new drive" smooth. Today a move orphans
the existing library: the watcher only scans a directory once (at
startup), files are identified by TMDB id with an exact-path dedup
key, and nothing recognises that a file at a *new* path is the same
content that used to live at an *old* path. The user is forced into
Clear-database / reboot folklore. The fix is move detection: when a
scan finds a new file that matches a now-missing known file, re-point
the existing entity to the new path instead of re-importing it.

## Status

Planning. Triggered by a user bug report (`Path.join([])` 500 + "moved
to a new HDD, cleared everything, only a reboot fixed it"). Two
robustness fixes that fell out of the investigation are **already
shipped**; the relink feature itself is designed (matcher = relative
path + filesize, auto, filesystem-injected test seam) with no code yet.

## Decisions made

Append-only log.

* `2026-05-30` — Root cause of "cleared, still won't pick up": `clear_database/0` deleted `WatchedFile` but left its `FilePresence` parent (plain column, no DB cascade). `FilePresence` is the scan's skip-ledger, so the post-clear watcher restart skipped every file on disk. Fixed by wiping `FilePresence` + orphaned `ExtraFile`. (commit `2695dc0d`)
* `2026-05-30` — Bare `/media-images` (built from a nil/empty image path, or a crawler) hit `Path.join([])` → 500. Now short-circuits to the graceful placeholder. (commit `3027a358`)
* `2026-05-30` — Move matcher = **relative-path + filesize**. No content hashing: a genuine move preserves both, and hashing is heavy I/O for the long tail of renames we deliberately don't cover.
* `2026-05-30` — **Auto-relink, logged, no confirmation modal.** A "move" is confirmed by the old path being *gone* on disk (distinguishes move from copy), which keeps false positives near zero — a prompt would be friction, not safety.
* `2026-05-30` — **Lazy size capture**: the scan stats only *new* files, so existing rows pick up a size the next time they're stamped. Pre-feature rows (size `nil`) fall back to relpath-only matching for the first move.
* `2026-05-30` — Test strategy: pure `MoveMatcher` + filesystem-injected `relink_moved_files/3` + a real-temp-dir integration scan. The integration test **is** the reproduction harness — the prod DB is shared with the :1080 dev server, so the user's scenario can't be reproduced live. Red→green on that test is the proof the feature fixes the report.

## Next steps

Build bottom-up, test-first. Each step lands with its tests.

1. **Schema + ingestion** — migration adding nullable `size` to `library_file_presences`; capture `size` in `FilePresence.stamp`/`stamp_many`; stat new files in `Watcher.scan_directory_with_paths` (watcher.ex:409). Safe/idempotent migration, lazy backfill.
2. **`Library.MoveMatcher`** (pure, `async: true`) — match new `{relpath, size}` against existing presence rows; single candidate → match, multiple → bail, `nil` size → relpath-only fallback. Moduledoc documents the matching contract.
3. **`Library.relink_moved_files/3`** (DataCase, FS injected via `exists?:` opt) — re-point `FilePresence` **and** the denormalised `WatchedFile`/`ExtraFile` path+watch_dir; verify old path gone (move vs copy); return `{relinked, still_new}`; broadcast `entities_changed`. Cases: move, copy (not relinked), ambiguous (skipped), size mismatch, `nil`-size fallback.
4. **Scan hook** — in `scan_directory_with_paths`, relink before `detect_file/2`; dispatch only `still_new` to the import pipeline; broadcast for relinked entities.
5. **Integration test** (real temp dir, ADR-016) — write file under `tmp/A`, scan (links entity), `File.rename` to `tmp/B`, repoint watch dir, scan again (call `Watcher.scan` directly — no inotify timing). Assert entity count stays **1** and resolves to the new path. Confirm red on pre-relink code.
6. **Discoverability** (deferred from the robustness pass) — surface the existing "Scan now" action in the **Library** settings section; today it lives only in *Services* (settings_live.ex:1807) and the console drawer, nowhere near watch-dir management.
7. **Wiki** — `Troubleshooting.md` "moved media won't show up" entry once the user-visible workflow settles.

## Completion criteria

* Moving files to a new path (same or new watch dir) re-points existing entities — no re-import, no duplicate entities — proven by the temp-dir integration test going red→green.
* Matcher is safe: copies and ambiguous matches are never silently relinked.
* No reboot and no Clear-database needed to recover a move.
* Wiki updated; the move workflow is documented for users.

## Pointers

* Shipped prerequisite fixes: commits `3027a358` (image plug), `2695dc0d` (FilePresence wipe).
* Key seams: `Watcher.scan_directory_with_paths/4` (watcher.ex:409 — the new-files/detect-file hook), `MediaCentaur.Library.FilePresence` (the skip-ledger), `MediaCentaur.Library.WatchedFile` (denormalised path), `MediaCentaur.Maintenance` (`resources_in_delete_order/0`).
* [ADR-016](../decisions/architecture/2026-03-01-016-test-env-filesystem-isolation.md) — temp-dir / persistent_term isolation for the integration test.
* [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md) — campaign convention.
* A throwaway visual model of the broken journey + relink options was generated at `tmp/move-data-model.html` (scratch; regenerate via visual-explainer if needed).
