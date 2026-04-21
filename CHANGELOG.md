# Changelog

User-facing release notes for Media Centarr. Internal refactors, test
changes, and dependency bumps with no user impact are omitted here —
see the git history for the full engineering trail.

## v0.18.1 — 2026-04-21

### Improved

- **TV series detail loads faster.** The first time you open a show
  with many seasons and episodes, the page now renders in a fraction
  of the previous time — the database layer was missing two indexes
  that made every show open trigger a full-table scan.
- **Library grid stays responsive during playback.** Progress updates
  while you're watching an episode no longer rebuild the entire grid
  behind the scenes; only the affected poster is refreshed. Libraries
  with hundreds of entries feel noticeably smoother.
- **Status page opens without hanging.** The /status page used to
  stall on first paint while it gathered stats, history, and storage
  measurements. Those now load in the background so the page renders
  immediately and fills in as the numbers arrive.
- **Track New Show modal opens faster.** The list of suggested shows
  is built from a single database query instead of loading everything
  into memory first.
- **Review page handles bulk approvals better.** Approving or
  dismissing many files in a row no longer rebuilds internal
  bookkeeping from scratch on every action.
- **Console drawer opens faster on big buffers.** If you've bumped the
  console buffer size above the default, opening the Console no
  longer copies the entire buffer up-front — only what you'll see,
  with the rest arriving live as new logs come in.
- **Releases refresh contends less with SQLite.** The periodic refresh
  of tracked shows now fans out only the TMDB fetches in parallel;
  the database writes happen one at a time, avoiding the occasional
  lock contention on slower disks.
- **Image backfill keeps TMDB busier.** The background image pipeline
  went from 4 to 8 concurrent workers, which cuts the time to
  populate artwork for a freshly-imported library nearly in half.
- **Acquisition queue processes more jobs at once.** The Oban
  acquisition queue went from 5 to 10 concurrent jobs for faster
  throughput when grabbing multiple releases.

## v0.18.0 — 2026-04-21

### Added

- **Capability gating on external integrations.** UI surfaces that depend
  on TMDB, Prowlarr, or the download client now only appear once you've
  explicitly tested that connection in Settings and it came back green.
  The Download sidebar entry stays hidden until Prowlarr tests green;
  the downloads queue panel hides (with a pointer to Settings) until
  the download client tests green; Track New Releases, the Rematch
  button in detail view, and Review's Search TMDB stay hidden until
  TMDB tests green. Tests are cleared automatically when you save new
  credentials, so changing a URL or key immediately re-hides the
  dependent features until you re-test.
- **TMDB "Test connection" button** on the Settings → TMDB page,
  matching the existing Prowlarr and download client pattern. Result
  persists with a relative-age display ("Connected · 3 min ago") and
  is cleared when the API key is saved.

## v0.17.0 — 2026-04-21

### Fixed

- **Detail view no longer closes when you click inside the Console
  drawer.** The dismiss-on-outside-click behavior is now scoped to
  the modal's backdrop rather than listening globally — clicks
  inside sibling overlays (Console, future popovers) stay
  self-contained. Applies to every modal: movie/show detail, Track
  New Show, delete confirmations, stop-tracking, cancel-download.

## v0.16.2 — 2026-04-21

Maintenance release — no user-visible changes. Restores a green CI
baseline (test isolation fix for systemd-supervised runners) and
renames an internal dev-only dependency.

## v0.16.1 — 2026-04-20

### Fixed

- **Detail view backdrop** now anchors to the top of the hero image
  instead of centering. When the source image is taller than the 21:9
  hero, the bottom crops away and the top of the composition is
  preserved — important for posters and title treatments that live near
  the top of the frame.

## v0.16.0 — 2026-04-20

### Added

- **Settings → Controls.** Remap every keyboard and gamepad binding.
  Each row has separate KEY and PAD columns; click the pencil to
  listen for a new key or pad button, clear to unset. Choose Xbox or
  PlayStation glyph styles. Reset per-category or all at once. New
  bindings take effect immediately without reload.

### Improved

- **Console component chips** now use a deliberate per-component color
  palette instead of randomly-assigned daisyUI semantic classes.
  Routine library logs no longer look like warnings, and faded-to-
  invisible chips are gone — every chip is distinct and readable in
  both themes.
- **Console → Systemd tab** now tails the live edge the way
  `journalctl -f` does: oldest entries at the top, newest at the
  bottom, scroll pinned to the bottom. Scroll up to read history;
  scroll back down and tail-follow resumes.

### Fixed

- **Settings → Controls column alignment.** KEY and PAD stay firmly
  aligned across every row in a category via a shared subgrid — longer
  keycaps ("Backspace") no longer push the surrounding columns around.

## v0.15.2 — 2026-04-19

### Improved

- **Documentation refreshed for the DB-managed-config world.** The
  README, GitHub Pages landing, contributor `docs/configuration.md`, and
  the public wiki (*Configuration File*, *Adding Your Library*,
  *Settings Reference*, *Prowlarr Integration*, *Download Clients*,
  *First Run*, *Troubleshooting*, *FAQ*) all now describe the current
  app-managed configuration flow. The shipped `defaults/media-centarr.toml`
  is documented as containing only `port` and `database_path`; every
  other setting is edited in *Settings* and persisted to the database.

## v0.15.1 — 2026-04-19

### Fixed

- **Settings → Library layout.** Watch-directory and excluded-directory
  rows no longer right-align paths or render the same path twice, and the
  images-directory line is hidden when it would just restate the
  default `{dir}/.media-centarr/images` location. Edit is now a pencil
  icon for visual parity with the trash icon next to it.
- **System → Storage path truncation.** The Database row stopped
  hard-cutting at 48 characters with a leading ellipsis — long paths now
  display in full and only collapse to a trailing CSS ellipsis when the
  viewport is genuinely too narrow.
- **System → "Watch directories" row** now opens *Settings → Library*
  instead of looping back to *System*.

### Improved

- **Settings sidebar url for System** is now `?section=system` (was
  `?section=overview`). Old bookmarks still work — a one-line redirect
  catches `?section=overview` and routes to `?section=system`.
- **System → Integrations** (was "Configuration") — the label now matches
  what the group actually contains: external-service readiness (TMDB,
  Prowlarr, Download Client, MPV).
- **System page** dropped the now-obsolete "Configuration" card whose
  subtitle claimed watch directories required editing `media-centarr.toml`
  and restarting. Watch directories are managed in the Library section.
- **Services → "Scan now"** uses the success tone per UIDR-003 (it
  sits alongside other action buttons like "Detect from Prowlarr").
- **TMDB → API Key** now includes a "get one at themoviedb.org" link
  below the input for first-time users.

## v0.15.0 — 2026-04-19

### New

- **Excluded directories are now managed in the app.** A new *Excluded
  Directories* card lives next to *Watch Directories* under *Settings →
  Library*. Add a path to skip a sub-tree inside one of your watch
  directories — handy for downloads-cache folders, trash bins, or any
  area with transient files you don't want indexed. Changes take effect
  immediately; no restart.

### Improved

- **All runtime configuration lives in the database.** Every setting
  that has a UI (TMDB key, Prowlarr, download client, MPV paths, extras
  and skip directory names, file-absence TTL, auto-approve threshold,
  release-tracking cadence, and excluded directories) is now edited
  exclusively in *Settings*. Your existing `~/.config/media-centarr/`
  TOML values are imported automatically on first boot, after which
  the TOML is no longer consulted for those keys — the DB is the
  single source of truth. Editing the TOML post-upgrade is a no-op;
  use the UI.
- **Tighter `media-centarr.toml`.** The shipped default config now
  contains only the two keys that genuinely have to live outside the
  database: the HTTP `port` and the `database_path` itself. Every
  other key was either migrated to the DB or deleted as unused
  (`recently_watched_count`, legacy `media_dir` fallback).

## v0.14.0 — 2026-04-19

### New

- **Watch directories are now managed in the app.** Open *Settings →
  Library → Watch Directories* to add, edit, or remove watch directories
  from the UI. No more editing the TOML config file or restarting the
  app — changes take effect immediately, starting or stopping the file
  watcher per directory. The dialog validates paths live (exists, is
  readable, not duplicated, not nested inside another configured
  directory) and previews how many video files and subdirectories it
  found. Each entry supports an optional display name and an advanced
  *images directory* override for putting the artwork cache on a
  separate (e.g. SSD) volume. Existing `watch_dirs` entries in your
  `media-centarr.toml` are imported automatically on first boot, after
  which the UI is the source of truth.

### Improved

- **Library scrolls all the way to the top when you reach the zone
  tabs.** Keyboard and gamepad up-navigation from the library grid now
  scrolls the page fully to the top when focus lands on the Continue
  Watching / Library / Upcoming tabs, instead of stopping flush with
  the tab row.

### Fixed

- **Dev builds no longer check GitHub for updates.** Development
  instances (running via `mix phx.server` or the dev systemd unit) skip
  the boot update check and the periodic six-hour check, and hide the
  Updates card in Settings. The in-app updater targets production
  binaries; dev builds update by rebuilding from source.

## v0.13.1 — 2026-04-19

### Improved

- **Clearer message when GitHub rate-limits update checks.** The
  anonymous GitHub API has a 60-requests-per-hour-per-IP cap; when we
  hit it the System page was showing a cryptic *"Update check error:
  HTTP 403"*. The updater now detects the rate-limit response (via
  `x-ratelimit-remaining`) and surfaces the friendlier *"GitHub rate
  limit reached. Try again after HH:MM UTC."* using the reset
  timestamp GitHub returns.
- **Last-known release stays visible during transient errors.** A
  failed check no longer clobbers the `latest_release` displayed on
  the card — the "See what's new" disclosure and the tag+date line
  now remain populated from the last successful check, with the error
  message shown alongside. No more brief "blank card" flash during a
  stale-to-fresh transition either.

## v0.13.0 — 2026-04-19

### New

- **Service card on Settings > System.** A new *Service* card shows the
  current systemd state (running / stopped / not installed / not
  running under systemd) as a coloured badge, and — when systemd is
  available — offers **Restart** and **Stop** actions with a
  confirmation dialog. Both actions use `systemctl --user --no-block`
  so they return immediately and the restart cycle completes
  asynchronously; the browser reconnects on its own when the BEAM is
  back.
- **Service details disclosure.** A *Show service details* toggle on
  the card reveals the full `systemctl --user status` output in a
  scrollable monospace panel — useful when triaging a failed restart
  or checking recent activity without leaving the page.

### Fixed

- **Image-downloader test flake.** `ImagesTest` and
  `ImageProcessorTest` both stubbed `Application.put_env(:media_centarr,
  :image_http_client, …)` globally. Under `async: true` their setups
  raced, causing the 404 test (and others) to occasionally see a
  stub from a neighbour — showing `{:image_open_failed, "Failed to
  find load buffer"}` instead of `{:http_error, 404, _}`. The
  override now lives in the process dict (per-process, auto-cleans on
  test exit) and sibling test files can no longer stomp on each
  other.

## v0.12.6 — 2026-04-19

### Fixed

- **Update-progress modal now covers the full page.** The modal was
  nested inside the Settings page's content grid, where its
  `position: fixed` backdrop was constrained by the surrounding flex
  layout. Moved it to the layout root — the same placement the rest
  of the app's modals use (`ModalShell.modal_shell`, `TrackModal`) —
  so the backdrop covers the entire viewport regardless of which
  settings section is active or how the page is scrolled.
- **Auto-restart at the end of an update now actually restarts the
  service.** The detached handoff shell runs under `env -i` for
  hygiene, which was stripping `XDG_RUNTIME_DIR` and
  `DBUS_SESSION_BUS_ADDRESS` — two variables `systemctl --user`
  needs to reach the user's systemd instance. Without them, the
  installer's `has_systemd_user` probe returned false, the unit
  never got reinstalled, and the service was never told to restart.
  The new release was staged correctly on disk, but the running BEAM
  kept serving the old version. The handoff now passes these vars
  through explicitly.

## v0.12.5 — 2026-04-19

### Improved

- **Status check-marks no longer look oversized.** The green ✓ and
  amber ⚠ indicators on the System page (Configuration card) and the
  update-progress modal are now the lighter `-mini` heroicon variants
  sized to match their adjacent text, instead of chunky `-solid`
  glyphs that sat visually above the baseline. Applied across every
  place these indicators show up.

## v0.12.4 — 2026-04-19

### Improved

- **Stuck-restart warning shows up faster.** The modal now waits
  6 seconds after the handoff fires before surfacing the diagnostic
  panel (was 30 seconds). A healthy restart completes in 2–3 seconds,
  so 6 is a comfortable buffer without making you stare at a dead
  spinner for half a minute.

## v0.12.3 — 2026-04-19

### Improved

- **Update progress modal shows the full checklist.** The apply dialog
  used to show one line that replaced itself on every phase transition.
  It now renders every step — *Downloading release*, *Extracting files*,
  *Installing and restarting* — as a persistent row that lights up and
  checks off as progress happens, so you can see where you are in the
  process at a glance.
- **Modal styling is correct.** The backdrop now covers the full
  viewport instead of leaving the page visible at the edges, and the
  panel uses the app's standard modal design (centered, clear dark
  backdrop with blur, scale-in animation).

### Fixed

- **"Restarting the service…" no longer hangs silently.** If the BEAM
  doesn't die within 30 seconds of the handoff being fired, the modal
  switches to a warning state showing the exact `systemctl --user
  restart media-centarr` command to run manually, with a copy button.
- **Handoff script now writes a diagnostic log.** The shell redirects
  its own stdout+stderr to `~/.cache/media-centarr/upgrade-staging/
  <version>-<random>/handoff.log` from its first instruction, so when
  an update doesn't finish cleanly you can see exactly how far the
  chain got. The redundant `nohup` wrapper was also removed —
  `setsid --fork` already creates a new session, and `nohup`'s stdio
  reopening was interfering with our redirect.

## v0.12.2 — 2026-04-19

### Fixed

- **Settings > System stuck showing an ancient release.** Manual and
  on-view update checks refreshed only the in-memory cache, while the
  durable `Settings.Entry` row kept whatever the scheduled cron last
  wrote. On every restart the old row re-hydrated the cache for 5
  minutes, so the "latest known" version could drift weeks behind
  reality. All check paths now dual-write — the two storage layers
  stay in sync — and the boot-time check fires unconditionally (the
  job's uniqueness constraint prevents piling on the cron).

## v0.12.1 — 2026-04-19

### Fixed

- **Download progress bar sat at 0% then jumped to 100%.** The updater
  now streams the release tarball and reports progress at every 1%, so
  the bar moves smoothly as the download proceeds. A short CSS
  transition on the bar itself (150ms ease-out) smooths the motion
  between percentage ticks.
- **"Update staged. Restarting the service…" got stuck forever.** The
  detached shell that hands control to the staged installer was losing
  its stdio to the closing Erlang port, which SIGPIPE'd the installer
  before `systemctl restart` fired. Fix: the handoff script redirects
  its own output to a log file in the staging directory, and the
  spawner now passes `:nouse_stdio` plus `setsid --fork` so the chain
  is fully detached before the port closes.

## v0.12.0 — 2026-04-19

### New

- **See what's new shows the full release notes.** The disclosure on
  the System card no longer truncates at 500 characters — it now
  renders the full release body in a contained, scrollable panel with
  smaller type so longer changelogs don't overwhelm the page.

### Improved

- **Settings sidebar.** The *Overview* page is now called *System*,
  matching what the card actually covers (version, updates, release
  notes). URLs and bookmarks are unchanged.
- **App card identity.** The tagline on the Media Centarr card has
  been replaced with the license and copyright line
  (*MIT License · © 2026 Shawn McCool*).

## v0.11.0 — 2026-04-19

### New

- **Escape hatches for when *Update now* fails.** The Updates card on
  Settings > Overview has a new *Prefer the terminal?* disclosure with
  three copy-button commands covering the common recovery paths
  (standard update, force-reinstall current version, full bootstrap).
  The failure dialog also shows the same fallback command inline so you
  can recover with a single copy-paste rather than hunting for docs.
- **`--force` on the CLI updater.** `media-centarr-install --update
  --force` reinstalls the current latest tag even when the version
  matches — useful when a previous in-app apply left partial state and
  you want to re-extract and re-migrate cleanly without bumping to a
  new release.
- **Troubleshooting section in the README.** A *When auto-update fails*
  block documents the recovery ladder (service restart → CLI update
  → `--force` → bootstrap reinstaller) so users who reach the README
  before the UI still find the fallback commands immediately.

## v0.10.2 — 2026-04-19

### Fixed

- **Retry after a failed update.** If *Update now* failed (network blip,
  bad checksum, anything), the next click reported *"an update is
  already in progress"* and stayed stuck until the service restarted.
  Retries now work correctly — a new attempt blows through the previous
  failure. The failure dialog also gains an explicit **Retry** button so
  you don't need to close and re-open.

## v0.10.1 — 2026-04-19

### Fixed

- **In-app updater failure.** *Update now* crashed with `Tarball
  rejected: tar_error ... :enoent` because the extractor was clearing
  its own staging directory — including the tarball it was about to
  read. The extractor now leaves the downloaded file in place and
  only tightens the directory permissions.

## v0.10.0 — 2026-04-19

### New

- **See what's new, right in Settings.** The Updates card on Settings >
  Overview now has a *See what's new* disclosure that expands to show
  the release notes for the latest version — no need to click through
  to GitHub to find out what changed.
- **Rich release notes on GitHub.** The release workflow now uses the
  real `CHANGELOG.md` entry as the GitHub release body, so the notes
  you see in-app and on GitHub are the same user-facing copy. No more
  generic "Linux x86_64 release" placeholders.

## v0.9.1 — 2026-04-19

### Fixed

- **Post-install URL.** The installer's success message showed the dev
  server's URL (`http://localhost:1080`) instead of the real production
  URL. It now prints `http://localhost:2160`, and honors a custom
  `port = NNNN` if you've set one in your `media-centarr.toml`.

## v0.9.0 — 2026-04-19

No user-facing changes in this release. Internal build-tooling cleanup
that completes the transition to in-app updates as the only supported
update path — the old `scripts/install` is gone, and the local release
script has been renamed to `scripts/preflight` to reflect its true role
as a pre-tag build check.

## v0.8.0 — 2026-04-19

### New

- **One-click updates.** Settings > Overview now has an *Update now* button
  that downloads, verifies, and installs the latest release. A progress
  modal shows what's happening, and the service restarts automatically
  when it's done.
- **Background update checks.** Media Centarr now checks for new releases
  every 6 hours and shows a notice on Settings > Overview when one is
  available — no need to click *Check for updates* to see if you're
  behind.
- **First-run prompts.** On a fresh install, the Library page links you
  straight to the *Configure library* settings when no watch folders
  are set up, and Settings > Overview reminds you to add a TMDB API key
  so artwork and metadata load.
- **Installer: autostart is now optional.** Pass `--no-service` to skip
  systemd setup, and use `media-centarr-install service install` or
  `service remove` to add or remove autostart later. Systems without
  a working systemd user session (WSL2 without systemd, some containers)
  install cleanly and print the manual start command.
- **Installer: clearer output.** Every install, update, and uninstall now
  prints what was changed on disk and how to undo it — no more hunting
  through docs for the right path to delete.
