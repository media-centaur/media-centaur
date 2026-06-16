---
title: Setting up acquisition
nav_label: Setup
part: Acquisition
slug: setting-up-acquisition
order: 12
---
Acquisition is optional, and it needs two things before any of the chapters that follow
work: **Prowlarr** (an indexer aggregator that searches your trackers) and a **download
client**. This chapter sets both up. Until they're configured and their connection tests
pass, the Downloads page and every grab button stay hidden — nothing here breaks the rest of
the app.

The chain — and the one rule that catches everyone:

```
Media Centaur → Prowlarr → download client → a media directory → Media Centaur watches it
```

**The download client's completed-download folder must sit inside a directory Media Centaur
watches**, or files download but never reach your library.

## Installing Prowlarr

| Method | How | What you get |
|---|---|---|
| **prowlarr-stack** (recommended) | `curl -fsSL https://raw.githubusercontent.com/media-centaur/prowlarr-stack/main/install.sh \| sh` | Prowlarr + qBittorrent + FlareSolverr + a VPN gateway, auto-configured, installed to `~/prowlarr-stack` |
| Docker Compose | `docker compose up -d prowlarr` | Prowlarr at `http://localhost:9696`; you run qBittorrent yourself |
| System package | See [prowlarr.com](https://prowlarr.com/) | Distribution-specific install |

The stack has its own lifecycle: `~/prowlarr-stack/update`, `./setup --reconfigure` (e.g. to
rotate the VPN), `~/prowlarr-stack/uninstall`.

## Configuring Prowlarr

1. **Add indexers** — Prowlarr → Indexers → Add Indexer. Public trackers need no account;
   private ones need credentials. (Skipped with the stack's defaults, but add your own for
   real coverage.)
2. **Register the download client** — Prowlarr → Settings → Download Clients → Add (the stack
   pre-registers qBittorrent).
3. **Point the client's completed folder inside a media directory** — e.g. `/mnt/media/Downloads/complete/` where `/mnt/media` is watched.
4. **Verify** — search an indexer in Prowlarr and grab one result; it should land in that folder.

## Connecting Media Centaur

Settings → Media → Acquisition:

1. **Prowlarr** — enter the **URL** (e.g. `http://localhost:9696`) and **API key** (Prowlarr →
   Settings → General → Security → API Key), then **Test connection**. It must pass for the
   Downloads page and grab buttons to appear.
2. **Download client** — choose the **Type** (qBittorrent today), enter its **URL** (e.g.
   `http://localhost:8080`) and credentials, then **Test connection**. Or press **Detect from
   Prowlarr** to auto-fill from Prowlarr's own client config.

Saving any field clears that integration's test result — re-test after a change.

## Download clients

Grabs route through Prowlarr, so **any client Prowlarr supports works**. The in-app queue view
and cancel button need a direct driver, and today only qBittorrent has one:

| Client | Grabs (via Prowlarr) | In-app queue & cancel |
|---|---|---|
| qBittorrent | yes | **yes** |
| Transmission, Deluge, rTorrent, SABnzbd, NZBGet, … | yes | not yet |

For qBittorrent, set its Web UI (default `http://localhost:8080`) credentials and a save path
inside a watched media directory. The client password is **never read from the config file** —
it's UI-only, so it can't leak into a dotfiles commit or a config backup.

> [!TIP]
> If a grab downloads but never appears in your library, it's almost always the path rule:
> the client finished the file somewhere Media Centaur isn't watching. Point the client's
> completed-download folder inside a media directory and re-grab.
