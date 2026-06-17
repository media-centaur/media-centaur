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

* [`showcase-comprehensive-coverage.md`](showcase-comprehensive-coverage.md) —
  **planning.** Expand the marketing showcase from well-covered static
  surfaces to the high-impact feature set that photographs well:
  movie collections, multi-season detail, acquisition decision/plan
  modals, status drill-ins/incidents, an available update, and
  per-entity language memory. Splits into PD/CC catalog expansion
  (owner-gated), seed-data (collections, credits, file tracks,
  incidents), `showcase_mode` stub seams (update-available + acquisition
  alternatives), and a tour expansion. Skips Guide/Setup/Danger-Zone/
  first-run by decision. PD-or-CC for every visible string.
* [`guide-book.md`](guide-book.md) —
  **All 19 chapters on `main` (unpushed); pending owner review before push.** In-app
  book-style guide at a deep-linkable `/guide` route (linked only from Settings → System,
  not the main nav) teaching the enthusiast operator how Media Centaur works — 19 chapters
  across 5 parts (Orientation, Your library, Watching, Acquisition, Operating it),
  mastery-depth, each researched against source, with a discovery slant (surface under-used
  capabilities). Portable markdown rendered to HEEx via Earmark; text-first; voice from the
  `writing-copy` skill. Full precommit green. Deferred: title filter, screenshots,
  full-text search, and the wiki exporter (separate campaign).
* [`upcoming-overhaul.md`](upcoming-overhaul.md) —
  **built; shipped to `main` (unpushed), pending release tag.** Overhauled
  `/upcoming` per the section-overhaul house style into a time-first forecast: an
  **editorial timeline rail with a quiet sticky mini-month companion** (mockup #6)
  — proximity-scaled hero cards, honest auto-grab status, "under pursuit →
  Downloads" deep-link, per-title detail slide-over, demoted management. All six
  phases done (`UpcomingFeed` view-model → components+stories → `UpcomingLive`
  rewrite → full input treatment), full `mix precommit` green, wiki updated.
  Remaining: live nav spot-check, release tag, wiki push, screenshot regen.
* [`pursuit-identity-and-lifecycle.md`](pursuit-identity-and-lifecycle.md) —
  **planning.** Composite pursuits die on their first landing:
  `IdentityVerifier` fuzzy-matches the filename against the *lead* unit
  and cancels the whole pursuit on mismatch (live S2+S3 pursuit nuked at
  one S03E07 landing; six torrents orphaned), and the twin `Satisfy`
  path closes a pursuit on the first verified file. Settled direction:
  provenance over filenames — file→unit identity from the grab-time
  envelope (`Pursuits.Identity` strategies 1–3), title-matching scoped
  to `prowlarr_query` + hashless fallback, mismatch = per-unit review
  flag, conclusion = aggregate over unit states. Sibling of
  `plan-solver-consolidation`. Shipped through v0.88.4; prod-verified
  2026-06-11 (a series pack landed per-unit without nuking the
  pursuit).
* [`plan-solver-consolidation.md`](plan-solver-consolidation.md) —
  **shipped v0.88.2; live re-plan verification remains.** The
  media-search plan solver grabbed overlapping releases: a real S2+S3
  plan produced 7 grabs / ~59.5 GB where 2 season packs sufficed (one
  4K single vetoed the S3 pack via the summed-quality ensemble
  comparison; the pack was then grabbed anyway for leftovers, next to
  ~11.6 GB of singles duplicating its content). Fixed in
  `Acquisition.Planner`: consolidation claims spans greedily, packs win
  at equal quality, upgrades are offer-as-swap only; regression test
  pins the shape.
* [`duplicate-episode-copies.md`](duplicate-episode-copies.md) —
  **planning.** When the library ends up with two playable copies of
  the same unit (1080p pack copy + 4K single), today's behavior is
  accidental: playback picks an arbitrary insertion-order WatchedFile,
  both files persist on disk, and nothing surfaces the duplication.
  Plan-level dedup is solved, but physical duplicates still arrive —
  swap a pack-covered unit (the pack still contains it), a pack lands
  with unwanted episodes, manual release-mode grabs, pre-v0.88.2
  residue. Scope: deterministic quality-aware playback pick, duplicate
  visibility + explicit reclamation, swap-time mitigation decision,
  wiki documentation. Takes over the file-pick follow-up
  `plan-solver-consolidation` scoped out. No code yet.
* [`external-dependency-health-classification.md`](external-dependency-health-classification.md) —
  **shipped v0.83.2; prod-reconcile remains.** Move download-client connectivity faults off the noisy `:log`
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
  mixed-protocol grab that the media-search planner (campaign complete
  2026-06-10; see git history) will drive.
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
