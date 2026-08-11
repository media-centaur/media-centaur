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

* [`input-system-1.0-pass.md`](input-system-1.0-pass.md) —
  **in progress — Phase 1 (Home).** Page-by-page keyboard/gamepad
  navigation pass for 1.0, fixing the *model* rather than each page's
  symptoms. Two conflated responsibilities get one owner each:
  **adjacency** (geometry, not index arithmetic — `findNearest()` has
  been dead code all along) and **reveal** (the input system, never
  CSS — `scroll-snap-type: x mandatory` was silently overriding
  `scrollIntoView` and clipping every focused card ~100px past the
  fold, measured and A/B-confirmed). Entering a zone lands on an item
  touching the edge you came through, which is what makes Coming Up's
  "never tile 3" fall out of the rule instead of a special case.
  Owner chose the coherent path over the cheap one. Mouse wheel over a
  scrolling row deferred.
* [`below-floor-releases.md`](below-floor-releases.md) —
  **planning — design not started.** When every findable release of a
  title is below the user's quality floor, the plan board says a bare
  "unfound" — indistinguishable from "doesn't exist on your indexers"
  (*The Magician* 2005: 6 real releases, all ≤720p/unlabeled, silently
  rejected). Movies have no offer path at all; TV offers cover scope,
  not quality. Campaign carries the diagnosis + open questions into an
  owner-led design session; no design decisions yet.
* [`cinematic-modal-unification.md`](cinematic-modal-unification.md) —
  **in progress — Phase 1 (frame extraction).** Every modal grounded in a
  TMDB identity renders the same cinematic shell (pinned orientation block
  over a fixed backdrop): the frame welded into ModalShell/DetailPanel is
  extracted with `:orientation`/`:body` slots, then the plan modal and
  Incoming title modal re-seat on it. Artwork follows a promotion ladder —
  hotlink while browsing, temporary local `TmdbArtwork` cache once a
  tracked item or non-terminal pursuit references the identity (swept at
  7 days since last use AND no hold), permanent library store on import.
* [`documentation-catch-up.md`](documentation-catch-up.md) —
  **planning.** A massive wiki / guide / documentation pass to catch
  everything up to date, probably including an updated showcase and webpage
  updates. Owner-directed follow-up to the usenet/multi-client work; starts
  with a full surface inventory (wiki pages, guides, repo docs, showcase
  screenshots, media-centaur.net) before any editing.
* [`detail-page-gpu-blur.md`](detail-page-gpu-blur.md) —
  **investigating.** Reported sustained GPU spike on the detail/now-playing
  modal, blamed on `background-attachment: fixed` + stacked `backdrop-filter`
  blur. Report's CSS claims partly wrong (no `.glass`@40px; detail page is the
  entity modal's `.modal-page-backdrop`, not `.page-backdrop`; the real
  full-viewport blur is the unmentioned `.modal-backdrop` scrim). Automated
  headless A/B ruled out the proposed fix as a main-thread lever but can't
  measure the GPU blur pass (SwiftShader). **Blocked on a hardware GPU profile**
  — checklist in the file; prime suspect is the `.modal-backdrop` blur.
* [`fit-aware-acquisition.md`](fit-aware-acquisition.md) —
  **built; uncommitted/unpushed, awaiting owner review.** Picking one
  episode no longer grabs the whole series. The planner gates pack grabs
  by **fit** (`wanted-in-span / total-aired-in-span`) against a
  user-set `pack_min_fit` (default 75% — "most of the span"); below it,
  episodes are grabbed individually and an over-broad pack is surfaced as
  a one-click **offer** rather than auto-grabbed. Gating is monotonic and
  opt-in (only plans with persisted `span_sizes`; movies/tracking drops
  unchanged). All 5083 tests green. Next: owner review, resolve the
  pre-existing `earmark` deps.audit blocker, commit/push/tag, then
  validate the 75% default in real use.
* [`friends-recommendations.md`](friends-recommendations.md) —
  **parked — v2 backbone (do not start until v1 is complete).** Friends, with
  send/receive show recommendations that one-click into the existing
  acquisition path — no central server we operate, strong privacy/control.
  Direction settled: **Nostr** (signed events = recs, followed pubkeys =
  friends, relays = the pipe; free public relays *or* self-hosted private
  relays — control on a slider), keypair identity, NIF Schnorr bundled in the
  release. Open: the core gesture (broadcast feed vs directed/encrypted DM vs
  both — Q4), payload shape, key/relay UX. Resume at the open-questions section.
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
* [`playable-item-versions.md`](playable-item-versions.md) —
  **planning.** First-class multi-version support for playable items:
  renditions (HDR/SDR, 2160p/1080p — second `WatchedFile`, shared
  progress) vs cuts (director's cut — second `PlayableItem`, own
  progress), per [ADR-059](../decisions/architecture/2026-07-12-059-cuts-vs-renditions.md).
  Default pick = highest quality; user selects the **active** version
  in the entity's Manage modal; entity-scoped "grab another version"
  bypasses the in-library guard (manual only). Absorbs
  `duplicate-episode-copies` (removed 2026-07-12): a duplicate is a
  version the user didn't ask for, reclaimed from the same modal.
  Phase 1 = renditions, Phase 2 = cuts; swap-time pack mitigation and
  auto-upgrade stay deferred. No code yet.
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
  **implemented 2026-07-10 — P0 (stack) live; MC-side P1–P3 built & committed
  the same day; remaining: wiki page + live smoke test (user enters the
  SABnzbd API key in Settings).** Extended downloads from a single client
  (qBittorrent) to a **set routed by protocol**, with SABnzbd as the first
  usenet driver. Prowlarr routes by protocol (two download clients); MC's
  work was the one-client → set refactor (`Dispatcher.drivers()`, merged
  multi-client `QueueMonitor`, protocol-routed cancel) plus the SABnzbd
  driver, two-slot config/Settings, per-slot capability tests, and the
  `{:auto_cancel, :download_failed}` terminal-failure rule. SABnzbd owns
  par2/repair/unrar; usenet completion reads from history (`storage` →
  `content_path`, two-phase capture on the existing identity machinery).
  Identity stays provisional (title-match → pin `nzo_id`) until real
  payloads exist. Spans two repos (this + `prowlarr-stack`). Enables — but
  does not build — the mixed-protocol grab that the media-search planner
  (campaign complete 2026-06-10; see git history) drives.
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
* [`instant-navigation.md`](instant-navigation.md) —
  **in progress.** Sub-100ms page transitions across the app: ETS
  projections behind every mount path, an explicit per-page mount query
  budget locked by `test/media_centaur_web/no_db_on_render_test.exs`,
  and UIDR-012 eager/sync rendering throughout. P1–P5 shipped; the
  settings-probe pass is the remaining phase, gated on a re-measure.
* [`unified-title-search.md`](unified-title-search.md) —
  **phase 1 complete.** One search idiom across Library, Incoming, and
  the media-search front door (UIDR-014), so a title is looked up the
  same way regardless of which page the user starts from.
