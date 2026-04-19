# Configuration

As of v0.14.0, virtually all runtime settings are managed in the app UI and stored in the SQLite database. The TOML file is now minimal — it contains only the two keys that must exist before the database can be opened.

## TOML file (minimal)

```
~/.config/media-centarr/media-centarr.toml
```

**Only two keys belong here:**

| Key | Purpose |
|---|---|
| `port` | TCP port the HTTP server listens on (default: `2160`) |
| `database_path` | Absolute path to the SQLite file |

Everything else (watch directories, excluded directories, TMDB API key, Prowlarr URL + key, download client, MPV path + socket dir + timeout, extras dirs, skip dirs, file absence TTL, recent changes days, auto-approve threshold, release-tracking refresh interval) is stored in the Settings DB and edited through the Settings UI.

## One-shot TOML migration

On first boot after upgrading from v0.13.x or earlier, Media Centarr reads any runtime keys present in the TOML file, imports them into the Settings DB, and then ignores the TOML for those keys from that point on. No data is lost. After the migration, editing the TOML keys that were imported has no effect — use the Settings UI instead.

## DB-managed settings (edit in the UI)

All of these live on the **Settings** page and apply immediately with no restart:

- **Library** — Watch Directories, Excluded Directories, file absence TTL, recent changes days
- **TMDB** — API key
- **Pipeline** — auto-approve threshold, extras dirs, skip dirs
- **Playback** — mpv path, socket dir, socket timeout
- **Release Tracking** — refresh interval, region
- **Prowlarr** — URL, API key
- **Acquisition / Download Client** — type, URL, username, password

## End-user documentation

- **[Configuration File](https://github.com/media-centarr/media-centarr/wiki/Configuration-File)** — the minimal TOML file and migration notes.
- **[Settings Reference](https://github.com/media-centarr/media-centarr/wiki/Settings-Reference)** — all in-app settings.
- **[Adding Your Library](https://github.com/media-centarr/media-centarr/wiki/Adding-Your-Library)** — adding watch directories via the UI.

## Contributor reference

`MediaCentarr.Config` details live in the module's `@moduledoc` (`lib/media_centarr/config.ex`).
