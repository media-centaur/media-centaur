# Acquisition

Media-centarr can search for and acquire media automatically or on demand. Acquisition is **optional** — the application works fully as a library manager without it. When Prowlarr is configured, additional capabilities unlock.

## What acquisition provides

**Manual search** — search for any movie or TV series across all configured indexers, see results ranked by quality, and send a grab directly from the UI.

**Automated acquisition** — when release tracking marks a tracked item as available, the system searches automatically and grabs the best available quality (4K preferred, 1080p accepted). If nothing is found, it retries every 4 hours.

## Requirements

Acquisition requires [Prowlarr](https://prowlarr.com/) — an indexer aggregator that connects your search sources (torrent/usenet indexers) to your download client (qBittorrent, Transmission, Deluge, SABnzbd, etc.).

Media-centarr talks only to Prowlarr. You configure your download client once inside Prowlarr, and Prowlarr routes grabs to it automatically.

## Setup

See [prowlarr-setup.md](prowlarr-setup.md) for full installation and configuration instructions.

Once Prowlarr is running and configured:

1. Add your Prowlarr URL and API key to `media-centarr.toml`:

```toml
[prowlarr]
url = "http://localhost:9696"
api_key = "your-api-key-here"
```

2. Restart media-centarr. The search nav link and acquisition controls will appear.

## Graceful degradation

When Prowlarr is not configured:

- The search page and nav link are hidden
- Release tracking cards show no acquisition controls
- All other features (library browsing, playback, metadata scraping) work normally

No configuration errors or warnings are shown — acquisition is simply inactive.

## Quality preference

Automated grabs prefer 4K (2160p/UHD). If no 4K release is found, 1080p is accepted. Releases below 1080p are never grabbed automatically. Manual search shows all qualities so you can choose.

## How downloads reach your library

When Prowlarr routes a grab to your download client, the completed download lands in your download client's configured directory. If that directory (or a parent of it) is one of media-centarr's watch directories, the Watcher detects the new file automatically and the pipeline processes it — scraping metadata, downloading artwork, and adding it to your library.

**The critical link:** your download client's completion directory must be inside a watch directory configured in `media-centarr.toml`. See [prowlarr-setup.md](prowlarr-setup.md) for the recommended directory layout.
