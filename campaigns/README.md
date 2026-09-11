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

* [`watchlist-single-entry-point.md`](watchlist-single-entry-point.md) —
  **shipped v1.22.0 2026-09-11; owner check open.** Adding a title to the watchlist and enabling
  release tracking are two acts, in that order, and the second happens only
  on the watchlist. The record already works that way (one title intent, one
  write path); what does not is four download-side controls that raise a
  title to Follow or Grab as a side effect (*Download all and track*, *Watch
  for releases*, *Also grab future episodes*, *Track these*) and the full
  ladder mounted on every title view. Phase 1 removes the four controls and
  their machinery (`TrackingHandoffs`, `Plan.grab_future`, `Want.provenance`);
  Phase 2 shows the ladder only where the watchlist is being looked at. Two
  owner decisions open: whether the bookmark-or-ladder form is chosen by the
  record's rung or by the surface, and whether the Library keeps the ladder
  for an owned, unlisted title. Absorbs the owner check left by
  `watchlist-and-release-tracking`.
* [`indexer-id-search.md`](indexer-id-search.md) —
  **Phase 1 shipped 2026-09-06; Phase 2 undecided.** Identify a title by
  identifier rather than by name. Phase 1 verifies identity using the ids
  already present in aggregated Prowlarr responses — `SearchResult` carries
  them, plans and pursuits snapshot them, and `TitleMatcher` treats a
  mismatching id as a rejection title parsing can never assert; the ±1-year
  tolerance now applies only to id-less results. Phase 2 would query by id
  per indexer (the aggregated `/api/v1/search` ignores `imdbId`; the
  per-indexer Newznab route honours it), which means owning the fan-out
  Prowlarr exists to provide — measure the coverage gain first (51 vs 49 on
  one film), and it may be declined.
* [`serial-test-audit.md`](serial-test-audit.md) —
  **planning.** Cut suite wall time by moving tests out of the serial phase
  where nothing forces them there. The serial phase is 45% of the tests and
  ~80% of the wall time; `DataCase` is serial because SQLite is, but 38 plain
  `ExUnit.Case, async: false` files are serial by decision. Each is either
  justified in a comment or converted. Prefer the fix that costs no wall time
  (raise a positive `assert_receive` ceiling; never a `refute_receive` one).
  `mix test --slowest` is not valid input — under load it inflates by
  contention. No code yet.
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
* [`macos-platform-support.md`](macos-platform-support.md) —
  **Phases 1–6 shipped 2026-05-21**: all seven `Platform.*` seams have
  Linux and macOS impls, CI is green on both OSes with
  `--warnings-as-errors`, every tag builds `darwin-arm64`, and the
  one-line installer supports Apple Silicon. Phase 7 (a real-Mac
  install + self-update smoke) waits on hardware or the first macOS user
  report — none has arrived.

## Complete

Files retired; git history holds the verbatim record. Each entry names
where any leftover went.

* **Watchlist and release tracking** — **shipped v1.16.0 2026-09-07; file
  retired 2026-09-11.** Four representations of one idea collapsed into one
  authored intent and one derived machine, three title modals into two
  ([ADR-065](../decisions/architecture/2026-09-07-065-tracking-reasons-and-the-derived-tracked-title.md),
  [UIDR-035](../decisions/user-interface/2026-09-07-035-two-title-surfaces.md));
  superseded in part by *Tracking is a person's act* below. Phase 6 ("a title
  resolves to one surface") was abandoned before planning: an owned title
  opened from the watchlist gets a stub with an *In library* hop, and that is
  accepted behaviour — the brief is in the retired file's history. Leftover:
  the owner check of the shipped surfaces, re-homed to
  `watchlist-single-entry-point` Phase 4.
* **Tracking is a person's act** — **shipped v1.17.0 2026-09-08; file
  retired 2026-09-11.** One authored record per title carrying the whole
  ladder (Off · Ignore · List · Follow · Ask · Grab · Default); the machinery
  is derived from it, and nothing but a person puts a title on it. Supersedes
  ADR-065 §2/§4/§5 ([ADR-066](../decisions/architecture/2026-09-07-066-one-ladder-per-title.md))
  and UIDR-035's separate de-listing verb ([UIDR-036](../decisions/user-interface/2026-09-07-036-one-control-per-title.md)).
  Design: [`docs/superpowers/specs/2026-09-07-tracking-is-a-persons-act-design.md`](../docs/superpowers/specs/2026-09-07-tracking-is-a-persons-act-design.md).
  No leftovers.
* **Instant hero backdrop** — **shipped v1.14.0 2026-09-07; file retired
  2026-09-11.** The Home hero backdrop paints in the mount frame on every
  return, at master resolution, from a JS-owned `ImageBitmap` cache
  ([UIDR-032](../decisions/user-interface/2026-09-06-032-page-hero-backdrops-paint-from-a-decoded-bitmap-cache.md);
  the Library and Incoming hosts were later removed by UIDR-033). Measured in
  the real shell: a 32–50 ms hero decode on 4 of 5 returns before, none after.
  The media-center shell moved from Vivaldi to Chromium 152 (launcher outside
  the repo). Leftovers, owner only: confirm arrow keys, gamepad and the FLIRC
  remote drive the Chromium shell; then delete `~/.config/vivaldi-mediacenter`
  and `~/scripts/media-centaur/run.vivaldi-backup`.
* **HTTP client unification** — **shipped v1.8.0 2026-09-04; file retired
  2026-09-11.** Every outbound HTTP request through `HttpClient.new/2`
  (Credo MC0029); an origin-freshness response cache with ETag revalidation
  for TMDB and Steam; an `:http` Status tile per upstream
  ([ADR-064](../decisions/architecture/2026-09-04-064-outbound-http-seam.md)).
  Plan: [`docs/plans/2026-09-04-http-client-cache-and-upstreams-panel.md`](../docs/plans/2026-09-04-http-client-cache-and-upstreams-panel.md).
  Leftover, deferred to whichever change next touches one of them: collapse
  `MetadataStats`, `Image.Stats`, `ScanStats` and `HttpClient.Stats` onto one
  attach/cast/snapshot base.
* **Test-suite determinism** — **complete 2026-09-08** (file retired; design in
  [`docs/plans/2026-09-08-test-suite-determinism-checkout-design.md`](../docs/plans/2026-09-08-test-suite-determinism-checkout-design.md),
  amendment in [ADR-049](../decisions/architecture/2026-05-22-049-testing-principles.md)).
  A full `mix test` passes or fails on the code, not on the order ExUnit
  picked: a sync test checks the machine out and back in
  (`MediaCentaur.Case` → `GlobalStateSandbox`), restoring what can be
  restored and failing the test that left anything else — a process, a
  table, a live task, a request no stub could answer. `:accepted` left the
  disposition vocabulary; MC0035/MC0036 are the static half; the `DataCase`
  drain and ~90 hand-rolled restores are gone. Verified at five seeds and a
  padded run, zero leaks; same wall time back to back. The rate-based
  `render_async` site got a content wait; `Database busy` did not appear in
  fourteen runs and is noted, not chased.
