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
* [`test-isolation-hardening.md`](test-isolation-hardening.md) —
  **shipped 2026-05-21.** Categories A/B/D/E closed; C/F
  watching brief. `MC0018 NoDbInOnExit` Credo check enforces
  Category A mechanically. `DataCase` snapshot+drain pattern
  isolates `:persistent_term` and Task.Supervisor children.
  Will be removed (git history is the archive) after the
  macos-platform-support Phase 5 push sequence proves CI stability
  through its commits.
* [`marketing-site-overhaul.md`](marketing-site-overhaul.md) —
  **design exploration.** Rebuild media-centaur.net to stop reading as
  AI-generated and be true to the product. Direction chosen: a
  streaming-interface site ("the landing page is a media center") using
  the app's real azure/slate/glass palette. Five mockups under `mockups/`;
  v2 (`5-streaming-home-v2`) in review. Folds in: no maturity label,
  desk-to-couch framing, summaries→feature-pages IA, Docker dropped from
  non-goals, macOS install corrected, `© Shawn McCool`, demo-clip hero.
