# Prowlarr Setup Guide

This guide covers installing Prowlarr, connecting it to your indexers and download client, and configuring media-centarr to use it.

## Overview

The acquisition stack has three components:

```
media-centarr → Prowlarr → Download client → watch directory → media-centarr
     (search)   (indexers)  (qBit/Transmission)   (Watcher picks up)
```

The critical link is that your download client must save completed downloads to a directory that media-centarr's Watcher is monitoring.

## Directory layout (recommended)

```
/mnt/media/
  Movies/         ← watch directory in media-centarr.toml
  TV/             ← watch directory in media-centarr.toml
  Downloads/
    complete/     ← download client saves here (inside a watch directory)
      Movies/
      TV/
    incomplete/   ← in-progress downloads (Watcher ignores incomplete files)
```

Add `/mnt/media` (or the specific subdirectories) to `watch_dirs` in `media-centarr.toml`.

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
| Category | `media-centarr` (optional, for organisation) |

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

## Configuring media-centarr

Add to `~/.config/media-centarr/media-centarr.toml`:

```toml
[prowlarr]
url = "http://localhost:9696"
api_key = "your-api-key-here"
```

If Prowlarr runs on a different host (e.g. in Docker with a custom network), adjust the URL accordingly.

Restart media-centarr (`systemctl --user restart media-centarr-dev` or `mix phx.server`). The **Search** link will appear in the navigation bar.

## Connecting downloads to the library

For acquired files to appear in your library automatically, the download client's save directory must be inside (or equal to) a directory in `watch_dirs`.

**Example `media-centarr.toml`:**

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

**Download completes but doesn't appear in library** — verify the download directory is inside a watch directory configured in `media-centarr.toml`. Check media-centarr's Console (press `` ` ``) for Watcher events.

**Connection error in Settings** — confirm Prowlarr is running and the URL in `media-centarr.toml` is reachable from the machine running media-centarr.
