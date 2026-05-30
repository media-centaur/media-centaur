---
status: in_progress
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

Core relink path **shipped and green** (`fec56c02`): `MoveMatcher` →
`size` ingestion → `relink_moved_files/3` → scan hook → real-filesystem
integration test. A move now re-points the existing entity instead of
re-importing; copies and ambiguous matches fall through to a normal
import. Remaining: discoverability (Scan-now in the Library settings
section) and the wiki entry. Two robustness fixes from the original
investigation shipped earlier (`3027a358`, `2695dc0d`).

## Decisions made

Append-only log.

* `2026-05-30` — Root cause of "cleared, still won't pick up": `clear_database/0` deleted `WatchedFile` but left its `FilePresence` parent (plain column, no DB cascade). `FilePresence` is the scan's skip-ledger, so the post-clear watcher restart skipped every file on disk. Fixed by wiping `FilePresence` + orphaned `ExtraFile`. (commit `2695dc0d`)
* `2026-05-30` — Bare `/media-images` (built from a nil/empty image path, or a crawler) hit `Path.join([])` → 500. Now short-circuits to the graceful placeholder. (commit `3027a358`)
* `2026-05-30` — Move matcher = **relative-path + filesize**. No content hashing: a genuine move preserves both, and hashing is heavy I/O for the long tail of renames we deliberately don't cover.
* `2026-05-30` — **Auto-relink, logged, no confirmation modal.** A "move" is confirmed by the old path being *gone* on disk (distinguishes move from copy), which keeps false positives near zero — a prompt would be friction, not safety.
* `2026-05-30` — **Lazy size capture**: the scan stats only *new* files, so existing rows pick up a size the next time they're stamped. Pre-feature rows (size `nil`) fall back to relpath-only matching for the first move.
* `2026-05-30` — Test strategy: pure `MoveMatcher` + filesystem-injected `relink_moved_files/3` + a real-temp-dir integration scan. The integration test **is** the reproduction harness — the prod DB is shared with the :1080 dev server, so the user's scenario can't be reproduced live. Red→green on that test is the proof the feature fixes the report.
* `2026-05-30` — Steps 1–5 landed: `MoveMatcher` (`bf1ced46` chain), `size` column + ingestion (`c6360814`), `relink_moved_files/3` (`bf1ced46`), scan hook + real-FS integration test (`fec56c02`).

## Known limitations / follow-ups

* **Live inotify single-file move** is not relinked — only the scan path runs relink. A bulk move surfaces via the startup scan when the watch dir changes (the reported scenario), but a single `mv` into a running watch dir while the app is up would import as new. Route the `:check_size` → `detect_file` path through relink if this matters.
* **New-path presence collision**: `relink_moved_files/3` rewrites the old `FilePresence` row's `file_path` to the new path; if a row already exists at the new path (rare — it'd have to be stamped under another dir), the unique constraint trips the transaction. Acceptable for now; guard (delete-stale-then-repoint) if it shows up.
* **Pre-feature rows are size-less**, so `list_relink_candidates/1` loads all `nil`-size rows on any scan with new files. Self-heals as files get re-stamped with size; revisit if it shows on large legacy libraries.

## Next steps

1. ~~**Discoverability** — Scan-now in the Library settings section.~~ Shipped `ff73cf2d` (Scan-now / Cancel footer on the Watch Directories card).
2. **Ship** — `/ship` (patch or minor) to release the shipped commits so the reporter and other users actually get the fixes + relink. Held back: two other agents had in-flight work and the move touched the shared prod DB, so the release timing/version is the user's call.
3. **Wiki** (held until the release version is known — the wiki gates behaviour by version, and this is unreleased). Ready-to-paste entry under `Troubleshooting.md`'s "The Watcher isn't detecting my files" section:

   ```markdown
   ### I moved my media to a new drive and the library looks empty

   Move your files, then point Media Centaur at the new location in
   **Settings → Library → Watch Directories** (edit the entry, or remove the
   old one and add the new path). On the scan that follows, Media Centaur
   recognises files that simply *moved* — same path within the watch
   directory, same size — and re-links them to their existing library
   entries, so your watch history and metadata are preserved. You can also
   press **Scan now** in **Settings → Library** to trigger it immediately.

   You should not need **Clear database** for a move. (Available in vX.Y+.)

   Caveats: a *renamed* or *re-encoded* file no longer matches and imports as
   new; a single file moved in while the app is running is picked up on the
   next scan.
   ```


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
