# Prowlarr Setup Guide

This guide covers installing Prowlarr, connecting it to your indexers and download client, and configuring media-centaur to use it.

## Overview

The acquisition stack has three components:

```
media-centaur → Prowlarr → Download client → watch directory → media-centaur
     (search)   (indexers)  (qBit/Transmission)   (Watcher picks up)
```

The critical link is that your download client must save completed downloads to a directory that media-centaur's Watcher is monitoring.

## Directory layout (recommended)

```
/mnt/media/
  Movies/         ← watch directory in backend.toml
  TV/             ← watch directory in backend.toml
  Downloads/
    complete/     ← download client saves here (inside a watch directory)
      Movies/
      TV/
    incomplete/   ← in-progress downloads (Watcher ignores incomplete files)
```

Add `/mnt/media` (or the specific subdirectories) to `watch_dirs` in `backend.toml`.

## Installing Prowlarr

### Docker Compose (recommended)

Add Prowlarr to your `docker-compose.yml`:

```yaml
services:
  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    volumes:
      - ./config/prowlarr:/config
    ports:
      - 9696:9696
    restart: unless-stopped
```

Start with `docker compose up -d prowlarr`. Prowlarr is then available at `http://localhost:9696`.

### System package

Prowlarr publishes packages for major Linux distributions. See [prowlarr.com](https://prowlarr.com/) for installation instructions.

## Configuring Prowlarr

### 1. Add indexers

In Prowlarr: **Indexers → Add Indexer**. Add your preferred torrent and/or usenet indexers. Public trackers (1337x, RARBG mirrors, etc.) work without accounts. Private trackers require credentials.

For best 4K coverage, add indexers that carry remux and UHD releases.

### 2. Add a download client

In Prowlarr: **Settings → Download Clients → Add**.

#### qBittorrent

| Field | Value |
|-------|-------|
| Host | `localhost` (or your Docker host IP) |
| Port | `8080` (default qBittorrent WebUI port) |
| Username | your qBittorrent username |
| Password | your qBittorrent password |
| Category | `media-centaur` (optional, for organisation) |

In qBittorrent, set the default save path to your `Downloads/complete/` directory. If using categories, set the category save path instead.

#### Transmission

| Field | Value |
|-------|-------|
| Host | `localhost` |
| Port | `9091` |
| URL Base | `/transmission/` |

#### Deluge

| Field | Value |
|-------|-------|
| Host | `localhost` |
| Port | `8112` |
| Password | your Deluge password |

#### SABnzbd (usenet)

| Field | Value |
|-------|-------|
| Host | `localhost` |
| Port | `8080` |
| API Key | from SABnzbd Settings → General |

### 3. Get your Prowlarr API key

In Prowlarr: **Settings → General → Security → API Key**. Copy this value.

### 4. Verify the setup

In Prowlarr: **Indexers**, click the search icon next to any indexer to confirm it returns results. Then click the download icon on a result to confirm the grab routes to your download client.

## Configuring media-centaur

Add to `~/.config/media-centaur/backend.toml`:

```toml
[prowlarr]
url = "http://localhost:9696"
api_key = "your-api-key-here"
```

If Prowlarr runs on a different host (e.g. in Docker with a custom network), adjust the URL accordingly.

Restart media-centaur (`systemctl --user restart media-centaur-backend-dev` or `mix phx.server`). The **Search** link will appear in the navigation bar.

## Connecting downloads to the library

For acquired files to appear in your library automatically, the download client's save directory must be inside (or equal to) a directory in `watch_dirs`.

**Example `backend.toml`:**

```toml
watch_dirs = [
  { dir = "/mnt/media/Movies" },
  { dir = "/mnt/media/TV" },
  { dir = "/mnt/media/Downloads/complete" },
]
```

With this setup, files downloaded to `/mnt/media/Downloads/complete/` are detected by the Watcher, processed through the pipeline, and added to the library automatically — no manual action needed.

## Troubleshooting

**Search returns no results** — check that at least one indexer is configured and working in Prowlarr (Indexers page, click the search icon to test).

**Grab succeeds but download never starts** — check the download client configuration in Prowlarr. Look at Prowlarr's logs (System → Logs) for errors.

**Download completes but doesn't appear in library** — verify the download directory is inside a watch directory configured in `backend.toml`. Check media-centaur's Console (press `` ` ``) for Watcher events.

**Connection error in Settings** — confirm Prowlarr is running and the URL in `backend.toml` is reachable from the machine running media-centaur.
