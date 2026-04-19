# Changelog

User-facing release notes for Media Centarr. Internal refactors, test
changes, and dependency bumps with no user impact are omitted here —
see the git history for the full engineering trail.

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
