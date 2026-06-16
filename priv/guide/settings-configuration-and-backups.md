---
title: Settings, configuration & backups
nav_label: Settings & backups
part: Operating it
slug: settings-configuration-and-backups
order: 19
---
Almost everything is configured in the app, on the Settings page. A small text file handles
only what's needed before the database is open. This chapter is where each setting lives and
how to back the whole thing up.

## What lives where

The bootstrap file `~/.config/media-centaur/media-centaur.toml` holds three keys only:

| Key | Purpose |
|---|---|
| `database_path` | Where the SQLite database lives (default: `~/.local/share/media-centaur/media-centaur.db`) |
| `port` | The port the web server listens on (default: `2160`) |
| `media_dirs` | Initial media-directory seed, used only on first run when none are set |

Everything else — TMDB key, Prowlarr and download-client details, mpv/ffprobe paths,
language preferences, retention windows, every toggle — lives in the Settings database and is
edited in the app. **A runtime setting placed in the TOML is ignored.** The database is the
single source of truth; changes made in the app take effect immediately, no restart.

## The Settings page

| Group | Sections | What's there |
|---|---|---|
| **System** | Version & build, database stats, Service, Integrations, Updates, Health Check | App version, DB size, integration readiness, restart/stop, run setup tour, the link to this guide |
| **Updates** | — | Automatic update checks (on/off), check interval, automatic install (on/off). Release builds only |
| **General** | Services, Preferences, Controls | Toggle watcher / pipeline / image pipeline / auto-grab; scan now; spoiler-free mode; remap keyboard & gamepad bindings |
| **Media** | Library, TMDB, Acquisition, Pipeline, Playback, Language, Release Tracking | Media directories & excluded dirs, file-absence TTL, TMDB key & auto-approve threshold, Prowlarr & download-client credentials, mpv/ffprobe paths, audio/subtitle preferences, refresh interval |
| **Infrastructure** | Library maintenance, Danger Zone | Repair missing images, re-fetch backdrops, refresh credits, re-derive bonus-feature names; clear database; refresh image cache |

Most day-to-day settings are under **Media** and **System**. The
[full per-setting reference](https://github.com/media-centaur/media-centaur/wiki/Settings-Reference)
documents every key, its default, and its effect.

## What to back up

| Path | Holds | Back up? |
|---|---|---|
| `~/.local/share/media-centaur/media-centaur.db` | Library, watch progress & history, every in-app setting | **Yes — this is almost everything.** |
| `<media dir>/.media-centaur/images/` | Cached artwork (one folder per media directory) | Optional — re-downloads from TMDB if lost |
| `~/.config/media-centaur/media-centaur.toml` | The three bootstrap keys | Optional — trivial to recreate |

Your video files are yours and live wherever you put them; the app never moves or modifies
them, so they aren't part of a Media Centaur backup. If you set a non-default `database_path`
or per-directory `images_dir`, back up those paths instead.

## How to restore

1. Install Media Centaur on the target machine.
2. Stop the service: `systemctl --user stop media-centaur`.
3. Copy `media-centaur.toml` back to `~/.config/media-centaur/`.
4. Copy `media-centaur.db` back to `~/.local/share/media-centaur/` (or your configured path).
5. Copy each `.media-centaur/images/` folder back into its media directory (optional — skip to re-download from TMDB).
6. Start the service: `systemctl --user start media-centaur`.

Your library, progress, and settings return exactly as they were; nothing needs re-scraping.

> [!TIP]
> If you edit the TOML expecting a setting to change and nothing happens, that's the model
> working as intended — only `database_path`, `port`, and the first-run `media_dirs` seed are
> read from it. Everything else is in the database; change it in the app.
