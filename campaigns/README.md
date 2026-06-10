# Campaigns

Multi-session work — initiatives that span many commits with
context worth preserving across sessions and contributors. One
markdown per campaign, **removed when complete** — git history is the
archive (see ADR-042's 2026-05-23 amendment).

See [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
for the full convention. The short version:

* **When**: spans 3+ sessions, has a definable end state, carries
  resumable context. Single-commit features don't qualify.
* **Format**: kebab-case filename, frontmatter with `status` /
  `started` / `last_updated`, sections **Goal / Status /
  Decisions made / Next steps / Completion criteria**.
* **Reconciliation rule**: when resuming a campaign, read the
  file, reconcile against `git log` and the code, update before
  writing any new code. Drift makes the file worse than nothing.

Use [`template.md`](template.md) as a starter.

## Active

* [`external-dependency-health-classification.md`](external-dependency-health-classification.md) —
  **planning.** Move download-client connectivity faults off the noisy `:log`
  incident track onto the existing `:subsystem` assessor track, so one qBit
  outage is one auto-closing incident instead of 2–3 stale duplicates from a
  transient blip. Codifies [ADR-054](../decisions/architecture/2026-06-08-054-external-dependency-faults-are-subsystem-health.md);
  a download-client `assess/0` over `QueueMonitor` health plus a `LogHandler`
  suppression marker for assessor-owned connectivity logs.
* [`download-stack-control-plane.md`](download-stack-control-plane.md) —
  **planning.** Mature the download infrastructure (`prowlarr-stack`) from a
  one-shot installer into a **managed component with a control plane**, shipped
  as a **new `download-stack` repo** that supersedes the old one. The reframe:
  install/configure/observe/reconfigure are the stack's *operational
  lifecycle*; a `curl | sh` installer only covers install — the real gap is a
  missing control plane. Stack owns that control plane; **MC stays thin**
  (change-axis isolation — MC moves only when the MC↔stack protocol changes).
  Config-as-truth (`stack.toml` + `apply` reconciler + read-only `status`), VPN
  routing becomes a **runtime toggle** not an install-time fork, **v1 contract
  is drain-before-change** (no live-migration of in-flight/seeding state), and a
  **versioned, loopback-only, confirm-in-MC provisioning handshake** lets the
  installer auto-wire MC ("detected MC on :2160 — configure?"). Greenfield-with-
  heritage: ports prowlarr-stack's proven parts; old repo removed at parity-
  plus-maturity. ADR-052 (amends ADR-035) is the first deliverable. Seven phases;
  no code yet. Design settled 2026-05-31.
* [`media-search-tmdb-acquisition.md`](media-search-tmdb-acquisition.md) —
  **planning.** A second acquisition entry point: start from a TMDB title,
  pick seasons/episodes, and let Media Centaur autonomously plan a coverage
  strategy (complete-series → season pack → per-episode) over what's available
  *now*, steer the plan, then execute it as one composite pursuit. Unifies
  acquisition on a single pursuit core — file search is adapted onto it (fast
  path; brace-expansion collapses into one pursuit) and media search layers
  TMDB enrichments + an opt-in release-tracking handoff on top. Best-available-
  now (no patience timers, no upgrades — time is release tracking's job);
  hard search-vs-pursuit boundary (unfound units are reported, never seeking
  leaves). Four phases planned; no code yet. Design settled 2026-05-31.
* [`usenet-download-client.md`](usenet-download-client.md) —
  **planning.** Extend downloads from a single client (qBittorrent) to a
  **set routed by protocol**, with SABnzbd as the first usenet driver, so a
  user can pursue releases without caring whether each lands via torrent or
  usenet. Prowlarr routes by protocol (two download clients); MC's real work
  is the one-client → set-of-clients refactor (`Dispatcher.drivers()`,
  multi-client `QueueMonitor` merge) plus a SABnzbd driver. SABnzbd owns
  par2/repair/unrar; usenet completion reads from history. Identity is
  explicitly provisional (no infohash → title-match → pin `nzo_id`), to be
  redesigned once a live setup exists. Verification bounded to stubs (no
  provider yet). Spans two repos (this + `prowlarr-stack`). Five phases;
  no code yet. Design settled 2026-05-31. Enables — but does not build — the
  mixed-protocol grab that [`media-search-tmdb-acquisition`](media-search-tmdb-acquisition.md)'s
  planner will drive.
* [`install-repro-matrix.md`](install-repro-matrix.md) —
  **planning.** Reproducible install environments for media-centaur and
  prowlarr-stack. Phase 1 (Linux Mint 22.3 only) spec written
  ([`docs/superpowers/specs/2026-05-27-install-repro-env-design.md`](../docs/superpowers/specs/2026-05-27-install-repro-env-design.md));
  six follow-on phases captured (Tier-1 cloud-image distros, Pop!_OS,
  pre-built shareable images via Packer+GHCR, `--from-local`,
  upgrade/uninstall scenarios, optional CI). Triggered by a tester
  hitting missing-package, first-run, and Docker-without-sudo failures
  on a fresh Mint install — and our inability to reproduce any of them
  locally.
* [`track-selection-source-of-truth.md`](track-selection-source-of-truth.md) —
  **planning.** Mislabeled `forced` subtitle tracks (e.g. Sample Show
  S01E01: a full 863-cue English track flagged `forced+default`) get
  auto-enabled on understood-language audio because the on-screen sub is
  mpv's auto-selection, not our resolver. Plan: parse `default` into
  `Track`, distrust `forced+default` tracks, and make `MpvSession`
  actively `set sid` so the resolver is the source of truth. Diagnosis
  confirmed against the real file; no code yet.
* [`macos-platform-support.md`](macos-platform-support.md) —
  resumed at Phase 5 (macOS impls). Seven Platform.* seams landed
  on the Linux side; CI matrix on both OSes is green and strict
  (`--warnings-as-errors`). Next up: `Autostart.Launchd`,
  `DriveProbe.BsdDf`, `LogSource.Files`, darwin-arm64 in
  `ReleaseArtifact`.
