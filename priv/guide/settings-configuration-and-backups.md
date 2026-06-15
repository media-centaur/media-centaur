---
title: Settings, configuration & backups
part: Operating it
slug: settings-configuration-and-backups
order: 18
---
Almost everything you configure lives in the database and is set in the app. A tiny text
file handles only what the app needs *before* the database is reachable. Knowing that split
saves you from a common mistake — editing the file and wondering why nothing changes.

## Where configuration lives

The bootstrap file (`~/.config/media-centaur/media-centaur.toml`) carries only three things:
the **database path**, the **port**, and an initial **media-directories seed** used the first
time the app starts with none set. That's it — the values needed to open the database and
start the web server.

Everything else — your TMDB key, Prowlarr and download-client details, mpv and ffprobe paths,
language preferences, retention windows, every toggle — lives in the Settings database and is
edited in the app. A runtime setting placed in the TOML is **ignored**. The database is the
single source of truth, so a stale config file can never quietly override what you changed in
the UI. Changes made in the app take effect immediately, without a restart.

## The Settings page

Settings is grouped in the sidebar: **System** (version, integrations, updates, the service
controls, and the link to this guide), **General** (service toggles, preferences, and the
keyboard/gamepad Controls), **Media** (media directories, TMDB, acquisition, playback,
language, release tracking), and **Infrastructure** (the maintenance actions and the Danger
Zone). Most of what you'll touch day to day is under Media and System.

## Backups

One thing matters above all: **the SQLite database**
(`~/.local/share/media-centaur/media-centaur.db` by default). It holds your library,
watch progress and history, and every setting. Back it up and you've backed up almost
everything. Add the small TOML for convenience.

Artwork (cached under a `.media-centaur/images` folder inside each media directory) is worth
keeping but not essential — it re-downloads from TMDB. Your video files are yours and live
wherever you put them; the app never moves or modifies them, so they're not part of a
Media Centaur backup.

To restore: install the app, stop the service, copy the database (and TOML) back into place,
optionally restore the image folders, and start the service. Your library, progress, and
settings come back exactly as they were — nothing needs re-scraping.

> [!TIP]
> If you ever edit the TOML expecting a setting to change and it doesn't, that's the model
> working as intended — only `database_path`, `port`, and the first-run `media_dirs` seed are
> read from it. Everything else is in the database; change it in the app.

In short: a three-key bootstrap file plus a Settings database that owns everything else (and
wins over the file); back up the database above all, treat artwork as recomputable, and your
video files were never the app's to keep. Full details live in the
[Configuration](https://github.com/media-centaur/media-centaur/wiki/Configuration-File),
[Settings](https://github.com/media-centaur/media-centaur/wiki/Settings-Reference), and
[Backup & Restore](https://github.com/media-centaur/media-centaur/wiki/Backup-and-Restore)
wiki pages.
