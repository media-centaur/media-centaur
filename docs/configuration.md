# Configuration

All runtime settings are managed in the app UI and stored in the SQLite database. The TOML file is minimal — it carries only **bootstrap state**: the values the app needs before the database can be opened, plus the initial media-directory seed.

## TOML file (bootstrap only)

```
~/.config/media-centaur/media-centaur.toml
```

**Only these keys are read:**

| Key | Purpose |
|---|---|
| `database_path` | Absolute path to the SQLite file |
| `port` | TCP port the HTTP server listens on (default: `2160`) |
| `media_dirs` | Initial media-directory seed, imported into the DB on first boot only (managed in the UI thereafter) |

Everything else (excluded directories, data directory, TMDB API key, Prowlarr URL + key, download client, MPV path + socket dir + timeout, extras dirs, skip dirs, file absence TTL, recent changes days, auto-approve threshold, release-tracking intervals, update behaviour) is stored in the Settings DB and edited through the Settings UI. **A runtime value placed in the TOML is ignored** — the database is the single source of truth.

## Media-directory seeding

`media_dirs` is the only key with first-boot seeding: if the Settings DB has no media-directory entry yet, any `media_dirs` in the TOML are imported once, after which the key is ignored and edits live in the UI. Runtime preferences are **not** imported from TOML — set them in Settings.

## DB-managed settings (edit in the UI)

All of these live on the **Settings** page and apply immediately with no restart:

- **Library** — Media Directories, Excluded Directories, file absence TTL, recent changes days
- **TMDB** — API key
- **Pipeline** — auto-approve threshold, extras dirs, skip dirs
- **Playback** — mpv path, socket dir, socket timeout
- **Release Tracking** — refresh interval, region
- **Prowlarr** — URL, API key
- **Acquisition / Download Client** — type, URL, username, password

## End-user documentation

- **[Configuration File](https://github.com/media-centaur/media-centaur/wiki/Configuration-File)** — the minimal TOML file and migration notes.
- **[Settings Reference](https://github.com/media-centaur/media-centaur/wiki/Settings-Reference)** — all in-app settings.
- **[Adding Your Library](https://github.com/media-centaur/media-centaur/wiki/Adding-Your-Library)** — adding media directories via the UI.

## Contributor reference

`MediaCentaur.Settings.Config` details live in the module's `@moduledoc` (`lib/media_centaur/settings/config.ex`).
