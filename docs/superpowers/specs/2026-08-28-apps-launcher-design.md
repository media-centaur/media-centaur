# Apps Launcher — Design

**Date:** 2026-08-28
**Status:** Approved design, pre-implementation

An "Apps" main-nav section: an app launcher for starting external applications
(Steam games, Minecraft, emulators) from the Media Centaur interface. Primary
persona: a kid with a gamepad launching a game; a parent manages the list.

## Glossary

| Term | Meaning |
|---|---|
| **App** | A launchable entry. User copy says "app"; code says `App`. |
| **Add-method** | A way of creating an App (Steam picker, manual form). Add-methods fill the same uniform App shape at add time. |
| **Origin** | Provenance metadata recorded on an App by its add-method (e.g. which Steam app id it came from). |
| **Launch** | Fire-and-forget detached spawn of the App's command. |

## Decisions

- **MVP add-methods:** Steam picker + manual command form. `.desktop` scan
  deferred (icon-theme resolution, junk filtering).
- **Lifecycle:** fire-and-forget. No running-state tracking, no kill button.
  `steam steam://rungameid/<id>` exits immediately (the Steam client owns the
  game process), so tracking cannot be truthful for Steam; keeping semantics
  identical for all apps is honest and matches the persona. A later
  per-app "managed" flag could add tracking where it is truthful.
- **Representation:** landscape banner cards only (Steam 460×215 header art).
  Both banner and 600×900 capsule art are cached at add time so a future
  poster view is a pure UI addition — but only one card variant is built and
  maintained (avoids a permanent 2× storybook/test tax).
- **Management:** on the Apps page behind a toolbar **Manage** entry (TV-detail
  Manage idiom). The default page is launch-only.
- **Architecture:** uniform App + add-time importers. Every App row has the
  same shape; the Steam picker just resolves a game to a command + artwork
  before saving. Launching has one code path and knows nothing about sources.
  A runtime source-dispatch behaviour was rejected as speculative — all
  sources launch identically under fire-and-forget.
- **Command format:** single shell string, run via `sh -c` under `setsid`.
  One line to type in the manual form; shell quoting/env behave as expected.
  This is the user's own machine — shell-injection framing does not apply.
- **Artwork architecture (unify-design pass):** app artwork is an instance of
  the app's existing non-library-artwork concept — an identity-keyed directory
  under `data_dir`, **disk as the ledger** (no path columns), URLs resolved
  from disk at read time, served by the existing `/media-images/*` plug with
  the `?w=` derivative ladder. Modeled on `MediaCentaur.TmdbArtwork`, minus
  TTL/holds (app art is permanent and deleted synchronously with its app).
  An earlier draft's separate `/app-images/*` plug and `banner_path` /
  `poster_path` columns were rejected as parallel representations.
- **Launcher not unified with mpv — explicit refusal.** mpv's spawn is
  session-coupled (IPC socket, log reader, exit classifier); a detached
  fire-and-forget spawn shares none of it. No existing duplication collapses.
- **Steam binary resolved at add time — explicit.** The stored command bakes
  in the launch invocation (native `steam` vs flatpak); the importer detects
  which once, at add time. The command is user-editable data afterward, same
  as any manual app.
- **No ETS projection for the Apps page — explicit.** Projections exist for
  library-scale instant-nav; a dozen rows read straight from the context.

## Context & boundary

New top-level context `MediaCentaur.Apps`:

```
lib/media_centaur/apps.ex        # facade
lib/media_centaur/apps/
  app.ex        # Ecto schema
  launcher.ex   # detached spawn
  steam.ex      # Steam root discovery, VDF/ACF parsing, art lookup
  artwork.ex    # owns cache layout + URL resolution; fetches via ImageFiles
```

`use Boundary, deps: [MediaCentaur.Settings, MediaCentaur.Library], exports: [App]`
(Library for `Image.web_path/1`, same as `TmdbArtwork`). The web layer adds
`MediaCentaur.Apps` to its deps.

## Data model

One table, `apps`:

| Column | Type | Notes |
|---|---|---|
| `name` | string, required | display name |
| `command` | string, required | single shell string |
| `origin` | map, default `%{}` | e.g. `%{"source" => "steam", "app_id" => 413150}`; manual: `%{"source" => "manual"}`. Keys documented in the `App` moduledoc. |

No artwork columns — disk is the ledger (see Artwork). Sort: alphabetical
(manual ordering deferred). Dedup: context-level origin check at add time —
no JSON indexes for a dozen rows.

## Steam discovery

Pure-Elixir parsing of Steam's VDF/ACF key-value format (no new deps):

1. Locate the Steam root: `~/.steam/steam`, `~/.local/share/Steam`, flatpak
   (`~/.var/app/com.valvesoftware.Steam/...`) — first that exists.
2. Read `steamapps/libraryfolders.vdf` for all library folders.
3. Read each `appmanifest_*.acf` → app id + name (installed games only).
4. Filter known non-games (Steamworks Common Redistributables, Proton,
   Steam Linux Runtime).

Artwork resolution per game: Steam's local `appcache/librarycache` first
(both the old flat `"<appid>_header.jpg"` layout and the newer per-appid
subdirectory layout), CDN fallback by app id. Launch command produced:
`steam steam://rungameid/<id>`.

## Artwork

`Apps.Artwork` owns the cache layout and resolution, modeled on
`MediaCentaur.TmdbArtwork`'s paths/urls sections:

- **Layout:** `{data_dir}/images/apps/{app_id}/banner.jpg` (460×215 header,
  used now) and `poster.jpg` (600×900 capsule, cached for a future poster
  view). Both fetched at add time via `MediaCentaur.ImageFiles`.
- **Disk is the ledger:** no DB columns. `Apps.Artwork.urls/1` resolves
  role URLs by `File.exists?` at read time (trivially cheap at this scale,
  self-healing) and builds URLs via `Library.Image.web_path/1`. Missing role
  → `nil` → the card renders its monogram fallback.
- **Serving:** the existing `ImageServer` plug already searches `data_dir`,
  so `images/apps/…` is served — with `?w=` derivatives and cache headers —
  with zero new serving code. One coherent extension: a `"banner"` stem in
  its placeholder-dims table (`{320, 150}`).
- **Deletion:** removing an app synchronously deletes its art directory and
  purges derivatives via `ImageFiles.purge_derivatives_for/1`. No TTL, no
  holds — app art is permanent while its app exists, and `TmdbArtwork.sweep/0`
  never walks `images/apps/`.

Manual apps: optional artwork field accepting a URL or local file path
(droppable if the form should be leaner); without art the card renders a
monogram fallback.

## Launching

`Apps.Launcher.launch/1` spawns `setsid -f sh -c <command>` via
`Port.open({:spawn_executable, ...})`. The intermediate process exits
immediately; the app lives in its own session and survives Media Centaur
restarts. No session tracking or supervision beyond the caller.

- Brief "Launching <name>" acknowledgment in the UI.
- Short client-side debounce against double-presses.
- `MediaCentaur.Log` component tag `:apps` for observability.
- Linux-only for now, consistent with playback.

## UI

- Route `/apps` (`AppsLive`, default `live_session`), always reachable by URL.
- Nav entry in the **Watch** group, icon `hero-rocket-launch`, gated by a new
  `Preferences.AppsVisibility` boolean (`show_apps`, **default off**), wired
  like the Watchlist precedent: `BooleanSetting` module → `exports:` entry →
  `SettingAware` tuple in the router → `:if={@show_apps}` link in
  `layouts.ex` → `settings_row` toggle + handler in Settings.
- Page: toolbar with **Manage**; banner-card grid (`data-nav-zone` /
  `data-nav-grid`); new `AppCards.banner_card` component + storybook story
  covering art and monogram-fallback states. The card keeps Steam art's
  native `aspect-[460/215]` ratio (forcing the existing 16:9 backdrop-card
  ratio would crop ~17% of the art) but shares the established card chrome —
  `card-hover`, `glass-inset`, rounded corners, nav-focus states — and the
  art-less fallback-variant idiom from `continue_watching_row`.
- Manage mode reveals **Add app** and per-card edit/remove. Add modal has two
  tabs: **Steam** (grid of discovered installed games with header art,
  already-added marked) and **Manual** (name, command, optional artwork).
  Edit modal reuses the manual form pre-filled, plus remove.
- Empty state: single hint pointing at Manage → Add app (page is otherwise
  blank, so the CTA duplicates nothing).
- Input system: `data-page-behavior="apps"`, `assets/js/input/apps_behavior.js`
  modeled on `library_behavior.js`, registered in `page_behavior.js`, with a
  bun test. Full gamepad support from day one — the controller persona is the
  point of the feature.

## Error handling

- Steam absent or no games → Steam tab explains itself; Manual tab always works.
- Art fetch failure → App saves without art, fallback tile, logged.
- Launch failure is mostly invisible by design (fire-and-forget); whatever
  `sh` reports before detaching is logged.

## Testing

Test-first per house policy; no network in tests (CDN art stubbed like TMDB):

- VDF/ACF parser unit tests on fixture files (generic placeholder names —
  no real game titles).
- Discovery tests against tmp-dir Steam layouts (old and new librarycache).
- Launcher tests asserting constructed argv via an injected spawn function —
  never actually spawning.
- `apps_live_test.exs`: grid render, manage mode, add manual app, remove.
- Storybook render coverage for `banner_card`; page smoke test; JS behavior
  test.

## Docs

- Wiki: new Apps page under *Using Media Centaur*; Settings-Reference entry
  for the toggle.
- CHANGELOG entry.
- `docs/GLOSSARY.md` gains **App**, **add-method**, **origin** at completion.

## Deferred

- `.desktop` file scan add-method.
- Poster view (art already cached).
- Manual ordering / favorites.
- Per-app "managed" lifecycle flag (running state / close, where truthful).
