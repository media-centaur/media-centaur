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
- **Acquisition** *(optional)* — search for and download media via Prowlarr. Works with any download client Prowlarr supports. See [Prowlarr Integration](#prowlarr-integration) below.
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

Copy the default config:

```bash
mkdir -p ~/.config/media-centarr
cp defaults/backend.toml ~/.config/media-centarr/backend.toml
```

Edit `~/.config/media-centarr/backend.toml`. At minimum, set your watch directories and TMDB API key:

```toml
watch_dirs = [
  { dir = "/mnt/media/Movies" },
  { dir = "/mnt/media/TV" },
]

[tmdb]
api_key = "your-tmdb-api-key"
```

See [Configuration](docs/configuration.md) for all options.

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
systemctl --user start media-centarr-backend-dev       # start
systemctl --user stop media-centarr-backend-dev        # stop
journalctl --user -u media-centarr-backend-dev -f      # logs
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

## Prowlarr Integration

Prowlarr is an indexer aggregator that enables media search and automated downloading. This integration is entirely optional — Media Centarr works as a library manager without it.

### How it works

1. You search for media in Media Centarr (or release tracking triggers an automated search)
2. Media Centarr sends a grab request to Prowlarr
3. Prowlarr routes it to your configured download client (qBittorrent, Transmission, Deluge, SABnzbd, etc.)
4. Your download client downloads the file and **moves it into one of your Media Centarr watch directories**
5. Media Centarr detects the new file, identifies it, and adds it to your library automatically

**The key step:** configure your download client to move completed downloads into a directory that Media Centarr is watching. Without this, downloaded files won't be picked up automatically.

### Setup

1. Install and configure [Prowlarr](https://prowlarr.com/) with your indexers and download client
2. In your download client, set the completed download location to one of your watch directories (e.g. `/mnt/media/Movies` or `/mnt/media/TV`)
3. Add to `~/.config/media-centarr/backend.toml`:

```toml
[prowlarr]
url = "http://localhost:9696"
api_key = "your-prowlarr-api-key"
```

4. Restart Media Centarr — the Search page and acquisition controls appear automatically

See [Acquisition](docs/acquisition/README.md) and [Prowlarr Setup](docs/acquisition/prowlarr-setup.md) for detailed instructions.

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
