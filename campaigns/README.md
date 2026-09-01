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
