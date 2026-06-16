---
title: Settings reference
part: Operating it
slug: settings-reference
order: 20
---
Every setting, by section. Most apply immediately on toggle or save and persist to the
database — no restart. For the config model and backups, see
[Settings, configuration & backups](/guide/settings-configuration-and-backups).

## System

Read-only status: app version and build, database location, integration readiness (TMDB,
Prowlarr, download client, mpv), and a **Run setup tour** button.

## Updates

Release builds only.

| Setting | Does | Default |
|---|---|---|
| Automatically check for updates | Polls GitHub for new releases in the background | On |
| Check every | Interval between checks (minutes; 15 floor) | 360 (6h) |
| Install updates automatically | Downloads and installs without asking; waits for playback to end | Off |

## General → Services

| Setting | Does | Default |
|---|---|---|
| Watchers | File-system monitoring of media directories | On |
| Pipeline | Metadata search and ingestion | On |
| Image Pipeline | Artwork download and processing | On |
| Auto-grab | Search and grab tracked releases as they air (global; per-title overrides exist) | On |
| Scan now | Action — force a full re-scan of every media directory | — |

## General → Preferences & Controls

| Setting | Does | Default |
|---|---|---|
| Spoiler-free mode | Blurs unwatched episode titles, descriptions, thumbnails | Off |
| Controls | Remap every keyboard/gamepad binding; Xbox/PlayStation glyphs; takes effect with no reload | — |

## Media → Library

| Setting | Does | Default |
|---|---|---|
| Data directory | Root for the app-managed artwork cache | Beside the database |
| Media Directories | Folders the watcher scans (path, optional name, optional images dir) | None — must set |
| Excluded Directories | Subpaths inside media dirs the watcher ignores | Empty |
| Show titles below posters | Library display toggle | On |
| File absence TTL | Days to keep records for files on an absent drive before cleanup (1 min) | 30 |
| Recent changes window | Lookback for "Recently added" (days, 1 min) | 3 |

## Media → TMDB

| Setting | Does | Default |
|---|---|---|
| API Key | TMDB credential; **Test connection** required for TMDB features | None |
| Auto-approve threshold | Confidence cutoff for automatic matching (0–1) | 0.85 |

## Media → Acquisition

Prowlarr and download-client setup is covered in
[Setting up acquisition](/guide/setting-up-acquisition). The auto-grab defaults (shown once
Prowlarr passes its test):

| Setting | Does | Default |
|---|---|---|
| Default mode | Auto-grab behaviour for newly tracked titles: all releases / ask / off | All releases |
| 4K patience | Hours to wait for 4K before falling back (0–720; 0 = grab now) | 48 |
| Minimum quality | Floor after patience expires: 1080p / 4K | 1080p |
| Maximum quality | Ceiling: 4K / 1080p | 4K |
| Maximum search attempts | Failed cycles before giving up on a release (1–50) | 12 |

Per-title overrides always win over these defaults.

## Media → Pipeline

| Setting | Does | Default |
|---|---|---|
| Extras directories | Folder names treated as bonus-feature containers | Extras, Featurettes, Special Features, Behind The Scenes, Bonus, Deleted Scenes |
| Skip directories | Folder names the pipeline ignores | Sample |
| Artwork resolution | Backdrop download resolution: 4K / 1080p (changing re-fetches backdrops) | 4K |

## Media → Playback

| Setting | Does | Default |
|---|---|---|
| mpv path | Absolute path to the mpv binary; playback off if missing | `/usr/bin/mpv` |
| ffprobe path | Path to ffprobe; missing → embedded-track detection skipped, sidecars only | `/usr/bin/ffprobe` |
| Socket directory | Where mpv IPC sockets live | `/tmp` |
| Socket timeout | How long to wait for mpv's socket on launch (ms; 100 min) | 5000 |

## Media → Language

Drives audio and subtitle selection (see
[Languages, subtitles & track selection](/guide/languages-subtitles-and-track-selection)).
Per-title overrides always win.

| Setting | Does | Default |
|---|---|---|
| Languages you understand | Ordered list you can follow without subtitles | Empty |
| Audio preference | Original first / understood first / any | Original first |
| Show subtitles | When audio not understood / always / never | When not understood |
| Subtitle language | Understood language / match audio | Understood |
| Subtitle style | Standard / prefer SDH | Standard |
| Forced subtitles | Fill gaps / always / never | Fill gaps |

## Media → Release Tracking

| Setting | Does | Default |
|---|---|---|
| Refresh interval | How often upcoming dates refresh from TMDB (hours; 1 min) | 6 |

## Infrastructure → Library maintenance (non-destructive)

Safe to re-run; all act on recomputable data (see [The mental model](/guide/the-mental-model)).

| Action | Does |
|---|---|
| Repair missing images | Re-queues images missing on disk for download |
| Re-derive bonus-feature names | Re-reads extra names from file paths (also runs at startup) |
| Re-fetch backdrops | Re-downloads backdrops at the current resolution |
| Refresh movie / series credits | Backfills cast/crew/IMDb id for older entries |
| Refresh movie subtitles | Detects tracks for movies imported before subtitle detection |

## Infrastructure → Danger Zone (destructive)

| Action | Does |
|---|---|
| Clear database | Permanently deletes all entries, files, images, and watch progress — re-scan rebuilds everything except progress |
| Refresh image cache | Deletes all cached artwork and re-downloads from TMDB |
