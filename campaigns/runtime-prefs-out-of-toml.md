---
status: planning
started: 2026-05-29
last_updated: 2026-05-29
---
# Runtime prefs out of TOML / Config façade

## Goal

`MediaCentaur.Config.update/get` is already a façade over `Settings`
(stored under `"config:<key>"` rows, seeded once at boot via
`migrate_runtime_keys_from_toml/1`). The next step is to drop both the
TOML schema entries and the `Config` façade for runtime preferences,
moving each to a typed accessor module over `Settings` (mirrors
`SpoilerFree`, `LibraryCardInfo`). The TOML file becomes purely
bootstrap state — things needed before the DB is reachable
(`database_path`, `port`, `watch_dirs`, `data_dir`).

The migration matters because the current façade hides what's a runtime
preference vs. what's bootstrap state, every new preference rebuilds
the same wiring (read cache, broadcast, on_mount seed), and the TOML
schema keeps drifting from reality as keys are added/removed.

## Status

Planning. `MediaCentaur.LibraryCardInfo` +
`MediaCentaurWeb.Live.LibraryCardInfoAware` shipped 2026-05-29 as the
first instance of the target pattern — see
`docs/superpowers/specs/2026-05-29-library-card-info-toggle-design.md`.
No existing `Config.runtime_settable_keys/0` entries have been migrated
yet.

## Decisions made

* `2026-05-29` — Target pattern: typed accessor module + `*Aware`
  on_mount trait, reading from `Settings.get_by_key/1`, no `Config`
  involvement. Modelled on `SpoilerFree` + `SpoilerFreeAware`.

## Migration waves

`Config.runtime_settable_keys/0` (see `lib/media_centaur/config.ex:43`)
splits into batches by call-site complexity and risk.

### Wave 1 — display / tuning knobs (low risk, low call-site count)
* `file_absence_ttl_days`
* `recent_changes_days`
* `release_tracking_refresh_interval_hours`
* `release_tracking_sweep_interval_minutes`
* `auto_approve_threshold`
* `showcase_mode`
* `setup_wizard_dismissed` (decide: display or bootstrap?)

### Wave 2 — paths / pipeline knobs (moderate; more callers)
* `extras_dirs`, `skip_dirs`, `exclude_dirs`
* `mpv_path`, `mpv_socket_dir`, `mpv_socket_timeout_ms`
* `ffprobe_path`

### Wave 3 — credentials (highest risk; `%Secret{}` wrapping)
* `tmdb_api_key`
* `prowlarr_url`, `prowlarr_api_key`
* `download_client_type`, `download_client_url`,
  `download_client_username`, `download_client_password`

### Stays in Config / TOML (bootstrap only)
* `database_path`
* `port`
* `watch_dirs`
* `data_dir`

## Next steps

1. Audit `defaults/media-centaur.toml` — which keys carry shipped
   defaults users actually rely on vs. which exist because they were
   tunable at install time. Drives what gets deleted vs. what gets a
   hard-coded default in the typed accessor.
2. Decide the home for `setup_wizard_dismissed` — it has bootstrap
   characteristics (read before any LiveView mounts) but is also a
   user-toggleable flag. Possibly stays in Config.
3. Wave 1: per-key, build a typed accessor + (if reactive) `*Aware`
   trait, migrate every `Config.get/update` call site, remove the
   entry from `@runtime_settable_keys`, drop the TOML schema field.
4. Wave 2.
5. Wave 3 — extend the accessor pattern with `%Secret{}` wrapping
   semantics on read; verify `:phoenix, :filter_parameters` coverage
   still holds.
6. Retire `Config.update/2`, `Config.load_runtime_overrides/0`,
   `Config.migrate_runtime_keys_from_toml/1`, and
   `Config.runtime_settable_keys/0` once the list is empty.

## Completion criteria

* `Config.runtime_settable_keys/0` is empty (or removed).
* `defaults/media-centaur.toml` contains only bootstrap keys.
* No production caller invokes `MediaCentaur.Config.update/2` for a
  user preference — every preference has its own typed accessor module
  over `Settings`.
* `Config.migrate_runtime_keys_from_toml/1` removed.
* `Config` moduledoc rewritten to reflect bootstrap-only scope.

## Pointers

* Current façade: `lib/media_centaur/config.ex` (especially
  `runtime_settable_keys/0` at line 43,
  `load_runtime_overrides/0`, `update/2`,
  `migrate_runtime_keys_from_toml/1`).
* Target pattern: `lib/media_centaur/spoiler_free.ex`,
  `lib/media_centaur_web/live/spoiler_free_aware.ex`.
* First instance: `MediaCentaur.LibraryCardInfo` +
  `MediaCentaurWeb.Live.LibraryCardInfoAware` (see spec
  `docs/superpowers/specs/2026-05-29-library-card-info-toggle-design.md`).
* TOML schema: `defaults/media-centaur.toml`,
  `lib/media_centaur/config.ex` `load_config/0` (line 401).
