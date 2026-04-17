<div align="center">

# Media Centarr

**A self-hosted media center for Linux that watches your library, identifies your media, and gets out of the way.**

[![Elixir](https://img.shields.io/badge/Elixir-1.15+-4B275F?logo=elixir&logoColor=white)](https://elixir-lang.org)
[![Platform](https://img.shields.io/badge/platform-Linux-informational?logo=linux&logoColor=white)](https://kernel.org)

Point it at your video directories. It identifies your movies and TV shows via TMDB, downloads artwork, tracks your progress, and plays everything through mpv — all from a real-time interface designed for the living room.

Zero-config SQLite database. No Docker. No transcoding server. No accounts.

</div>

> **Alpha software.** Media Centarr is functional for daily use but under active development. Expect rough edges and occasional breaking changes between releases.

---

## Features

- **Library management** — watches directories for new video files, identifies movies and TV shows via TMDB, and downloads artwork automatically. Low-confidence matches are held for manual review instead of guessing wrong.
- **Playback** — plays everything through mpv via IPC. Tracks your progress, resumes where you left off, and advances to the next episode automatically.
- **Release tracking** — track upcoming movies and TV seasons from your library. Media Centarr monitors TMDB daily and shows what's coming and when.
- **Acquisition** *(optional)* — search and queue downloads via Prowlarr. All acquisition features are gated behind a working Prowlarr install with a download client configured. Live queue progress and in-app cancellation currently require qBittorrent; adding other clients is a small driver — see [Prowlarr Integration](#prowlarr-integration).
- **Living room UI** — keyboard and gamepad navigation, large artwork, dark-first design. Built to drive a TV from the couch, not a desktop browser.
- **Real-time** — every change (new file, metadata fetched, playback started) appears instantly. No polling, no refresh.

---

## Requirements

- Elixir 1.15+ and Erlang/OTP 26+
- SQLite3
- mpv
- inotify-tools
- A free [TMDB API key](https://www.themoviedb.org/settings/api)

**Arch Linux:**
```bash
sudo pacman -S elixir sqlite mpv inotify-tools
```

**Debian/Ubuntu:**
```bash
sudo apt install elixir sqlite3 mpv inotify-tools
```

---

## Installation

```bash
git clone https://github.com/media-centarr/media-centarr.git
cd media-centarr
mix setup
```

---

## Configuration

**Most settings are edited in the app's Settings page** — TMDB API key, Prowlarr credentials, download client, playback options, pipeline tuning, and more. Changes apply immediately and persist to the database; no restart required.

A small number of **structural settings** must be in the TOML config file because they're needed before the app boots. The minimum you need to bootstrap is the list of directories to watch:

```bash
mkdir -p ~/.config/media-centarr
cp defaults/media-centarr.toml ~/.config/media-centarr/media-centarr.toml
```

Then edit `~/.config/media-centarr/media-centarr.toml` and set `watch_dirs`:

```toml
watch_dirs = [
  { dir = "/mnt/media/Movies" },
  { dir = "/mnt/media/TV" },
]
```

TOML-only settings:

| Setting | Why it's in TOML |
|---|---|
| `watch_dirs` | Needed before the Watcher starts |
| `exclude_dirs` | Needed before the Watcher starts |
| `database_path` | Needed before the database opens |
| Per-watch-dir `images_dir` | Tied to `watch_dirs` |

Everything else (TMDB, Prowlarr, download client, playback, pipeline, release tracking, library tuning) is editable in the Settings page once the app is running. The download-client password is **only** settable via the UI by design — it is never read from TOML so it can't be accidentally committed to dotfiles or included in config backups.

The TOML file accepts defaults for most UI-editable settings too, which can be useful for scripted deploys. See [Configuration](docs/configuration.md) for the full reference.

---

## Running

```bash
mix phx.server
```

Open [http://localhost:4001](http://localhost:4001). Enable the watcher and pipeline from the Settings page to start scanning your library.

---

## Running as a Service

### Development

```bash
scripts/install-dev                                    # install systemd user service
systemctl --user start media-centarr-dev       # start
systemctl --user stop media-centarr-dev        # stop
journalctl --user -u media-centarr-dev -f      # logs
```

### Production release

```bash
scripts/release    # build release
scripts/install    # install to ~/.local/lib/media-centarr/ and set up systemd
```

Before running a production release, generate and set a secret key:

```bash
export SECRET_KEY_BASE="$(mix phx.gen.secret)"
```

Add this to your shell profile or the systemd unit's `Environment=` directives. See [Getting Started](docs/getting-started.md) for full release instructions.

---

## Backup

Your library data lives in three places. Back up all three and you can restore a working install onto a new machine.

| Path | What's in it |
|---|---|
| `~/.local/share/media-centarr/media_library.db` | The SQLite database — library entities, watch progress, watch history, settings edited in the UI (TMDB key, Prowlarr credentials, etc.), release tracking, acquisition grabs. This is the single most important file. |
| `<watch_dir>/.media-centarr/images/` | Downloaded artwork (posters, backdrops, logos, thumbs). One such directory lives inside **each** of your `watch_dirs`. Losing these means re-downloading from TMDB; it's not catastrophic, but it's bandwidth and time. |
| `~/.config/media-centarr/media-centarr.toml` | The TOML config — watch directories, exclude directories, optional custom database path. Small and easy to regenerate by hand if lost, but backing it up avoids the re-typing. |

Notes:

- If you configured a non-default `database_path` in your TOML, back up that path instead of `~/.local/share/media-centarr/media_library.db`.
- If you configured a custom `images_dir` per watch directory, back up those paths instead of the default `.media-centarr/images/` location.
- `SECRET_KEY_BASE` is **not** data — it's a per-install secret. You can regenerate it (`mix phx.gen.secret`) on a restore; doing so invalidates any signed cookies / sessions, which is harmless for a single-user LAN install.
- Your video files themselves are owned by you and live wherever you put them. Media Centarr never moves, deletes, or modifies them.

A simple nightly backup of the three paths above (e.g. rsync to another disk, or restic/borg to remote storage) is sufficient.

---

## Prowlarr Integration

Prowlarr is an indexer aggregator that enables media search and automated downloading. This integration is **entirely optional** — Media Centarr is a full library manager without it.

All acquisition features are gated behind two pieces of working infrastructure:

1. A running Prowlarr with your indexers configured
2. A download client that Prowlarr is configured to use (Prowlarr does the routing; the client does the actual downloading)

Without both, the Search and acquisition UI will not appear.

### How it works

1. You search for media in Media Centarr (or release tracking triggers an automated search)
2. Media Centarr sends a grab request to Prowlarr
3. Prowlarr routes it to *its* configured download client
4. Your download client downloads the file and **moves it into one of your Media Centarr watch directories**
5. Media Centarr detects the new file, identifies it, and adds it to your library automatically

**The key step:** configure your download client to move completed downloads into a directory that Media Centarr is watching. Without this, downloaded files won't be picked up.

### Supported download clients

The *grab* path works with any client Prowlarr supports. Prowlarr ships drivers for most common torrent and usenet clients — qBittorrent, Deluge, Transmission, rTorrent, µTorrent, Flood, Aria2, SABnzbd, NZBGet, and more (see [Prowlarr's Download Clients documentation](https://wiki.servarr.com/prowlarr/settings#download-clients) for the current list).

For the `/download` page's live queue view and in-app cancel button, Media Centarr talks to your download client directly and needs its own driver for that client. **Today only qBittorrent has a driver.** There is no architectural reason other clients aren't supported — the driver layer is deliberately pluggable (see [Adding a download-client driver](#adding-a-download-client-driver) below). If you'd like support for Transmission, Deluge, SABnzbd, NZBGet, or anything else, please [open a GitHub issue](https://github.com/media-centarr/media-centarr/issues/new) describing which client and which credentials you have available for testing.

In the meantime: using any non-qBittorrent client still works end-to-end. Grabs go through Prowlarr, files land in your watch directory, and the library ingests them. The only thing missing is the in-flight queue view and cancel button.

### Setup

1. Install and configure [Prowlarr](https://prowlarr.com/) with your indexers and download client
2. In your download client, set the completed-download location to one of your watch directories (e.g. `/mnt/media/Movies` or `/mnt/media/TV`)
3. Add Prowlarr credentials to `~/.config/media-centarr/media-centarr.toml`:

   ```toml
   [prowlarr]
   url = "http://localhost:9696"
   api_key = "your-prowlarr-api-key"
   ```

4. *(Optional, qBittorrent only today)* Add download-client credentials to enable the `/download` page queue view:

   ```toml
   [download_client]
   type = "qbittorrent"
   url = "http://localhost:8080"
   username = "admin"
   password = "..."
   ```

   The Settings UI can pre-fill these by querying Prowlarr's configured clients.

5. Restart Media Centarr — the Search page and acquisition controls appear automatically

See [Acquisition](docs/acquisition/README.md) and [Prowlarr Setup](docs/acquisition/prowlarr-setup.md) for detailed instructions.

### Adding a download-client driver

Media Centarr's download-client layer is a pluggable `@behaviour`, so adding a new client is a small, contained piece of work. To add one:

1. **Implement the behaviour** at `lib/media_centarr/acquisition/download_client/<client_name>.ex`. The callbacks are defined in `lib/media_centarr/acquisition/download_client.ex`:

   | Callback | Returns | Purpose |
   |---|---|---|
   | `list_downloads(filter)` | `{:ok, [QueueItem.t()]} \| {:error, term()}` | Active / completed / all downloads for the `/download` page. `filter` is `:active \| :completed \| :all`. |
   | `test_connection()` | `:ok \| {:error, term()}` | Used by the Settings UI "Test connection" button. |
   | `cancel_download(id)` | `:ok \| {:error, term()}` | Remove the torrent/nzb and its partial data. `id` is whatever identifier your driver emitted in `QueueItem.id`. |

2. **Emit a normalized `QueueItem`** for each entry. The struct lives at `lib/media_centarr/acquisition/queue_item.ex`:

   | Field | Required | Notes |
   |---|---|---|
   | `id` | ✓ | Client-specific identifier. Passed back to `cancel_download/1`. |
   | `title` | ✓ | Display name. |
   | `status` |   | Raw client-supplied status string, kept verbatim (e.g. qBittorrent's `"pausedDL"`, `"stalledUP"`). Surfaces unknown values in the UI as a tooltip. |
   | `state` |   | Normalized atom for UI grouping: `:downloading \| :stalled \| :paused \| :completed \| :error \| :other`. |
   | `download_client` |   | Display name of the client ("qBittorrent", "Transmission", etc.). |
   | `indexer` |   | Tracker / category / group name if the client exposes it. |
   | `size` |   | Total size in bytes. |
   | `size_left` |   | Remaining bytes. |
   | `progress` |   | Percent, `0.0`–`100.0`. |
   | `timeleft` |   | Formatted ETA string (e.g. `"2h 30m"`, `"45s"`). `nil` for seeding/unknown. |

   Add a `QueueItem.from_<client>/1` builder that converts the raw client response into this struct, mirroring `from_qbittorrent/1`.

3. **Register the driver** by adding one clause to `Dispatcher.driver/0` in `lib/media_centarr/acquisition/download_client/dispatcher.ex`, mapping the `:download_client_type` config string (e.g. `"transmission"`) to your new module.

4. **Test it** — `test/media_centarr/acquisition/download_client/qbittorrent_test.exs` is the reference test pattern; mirror its structure.

That's the whole contract. No other code needs to change.

---

## Documentation

- [Getting Started](docs/getting-started.md) — installation, configuration, running, and release
- [Configuration](docs/configuration.md) — all config options with defaults
- [Architecture](docs/architecture.md) — system overview and component relationships
- [Pipeline](docs/pipeline.md) — how files are processed from detection to library
- [Playback](docs/playback.md) — mpv integration, progress tracking, and resume logic
- [Acquisition](docs/acquisition/README.md) — Prowlarr integration, manual search, automated grabs

---

## License

[MIT License](LICENSE) — Copyright (c) 2026 Shawn McCool

---

## Acknowledgments

<a href="https://www.themoviedb.org">
  <img src="https://www.themoviedb.org/assets/2/v4/logos/v2/blue_short-8e7b30f73a4020692ccca9c88bafe5dcb6f8a62a4c6bc55cd9ba82bb2cd95f6c.svg" alt="TMDB" width="120">
</a>

This product uses the TMDB API but is not endorsed or certified by TMDB.
