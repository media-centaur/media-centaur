# Changelog

User-facing release notes for Media Centarr. Internal refactors, test
changes, and dependency bumps with no user impact are omitted here —
see the git history for the full engineering trail.

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
