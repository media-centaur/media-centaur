---
status: planning
started: 2026-07-12
last_updated: 2026-07-12
---
# Playable-item versions: renditions, cuts, and the duplicate policy

## Goal

Make multiple versions of one movie or episode a first-class feature:
intentional renditions (HDR/SDR, 2160p/1080p) and cuts (director's
cut) that the user can acquire, see, pick between, and delete — with
accidental duplicates handled by the same surface. Absorbs the
`duplicate-episode-copies` campaign (removed 2026-07-12; its context
and ingress paths are folded in below): a duplicate is a version the
user didn't ask for, and its reclamation is one action in the version
UI.

## Status

Planning — design settled ([ADR-059](../decisions/architecture/2026-07-12-059-cuts-vs-renditions.md)),
no code. Triggered by a real need: grabbing an SDR copy of an HDR film
for comparison, and discovering the second file would be invisible and
unplayable through the UI.

## Context (verified in code 2026-07-12)

* **Schema is ready** — ADR-047 reified `PlayableItem` precisely so a
  container can hold multiple playable units (cuts, `name` override
  field unused so far) and a `PlayableItem` can hold multiple
  `WatchedFile`s (renditions). No structural migration expected.
* **Playback pick is accidental** — `Library.populate_leaf_content_url/1`
  takes the head of an unordered `watched_files` preload;
  `Library.playable_file_path/1` orders by `inserted_at asc`. Two
  paths, potentially disagreeing, neither quality-aware.
* **Acquisition dead-ends on owned movies** — `plan_create` no-ops when
  `movie.in_library?`, the plan button is disabled, and
  `ReleaseTracking.Wants` filters `not release.in_library`, so no want
  and no auto-grab. The only second-grab path today is the global
  Release-mode omnibox search ("Grab selected"), unscoped and unguarded.
* **Import appends blindly** — a second identified file for a known
  entity becomes another `WatchedFile` on the same `PlayableItem`
  (`Library.Inbound.link_file/2` → `Library.link_file!` dedups by
  `file_path` only). No rendition-vs-cut classification, no dedup, no
  review.
* **No rendition metadata** — `WatchedFile` carries no
  resolution/dynamic-range/codec/size; parse metadata dies with
  `PendingFile`.
* **Known duplicate ingress paths** (from `duplicate-episode-copies`):
  swap a pack-covered unit to a single (the pack still delivers its
  copy); a pack lands with unwanted episodes; manual release-mode
  grabs; pre-v0.88.2 solver residue (~11.6 GB known on disk).

## Decisions made

* `2026-07-12` — Cut vs rendition model: cuts are `PlayableItem`s (own
  progress), renditions are `WatchedFile`s (shared progress).
  ([ADR-059](../decisions/architecture/2026-07-12-059-cuts-vs-renditions.md))
* `2026-07-12` — Default pick = highest quality, deterministic; user
  override = selecting the **active** version in the entity's Manage
  modal. Owner call.
* `2026-07-12` — Absorb `duplicate-episode-copies` (owner accepted the
  recommendation): one model, one policy, one wiki story. Its
  swap-time-mitigation open question is inherited as deferred scope.
* `2026-07-12` — Rendition metadata is a deriver (ADR-057), from
  filename parse + file probe.
* `2026-07-12` — "Grab another version" is manual-only, scoped to the
  entity (detail page); auto-upgrade stays out of scope (the offers
  seam already exists for that future).

## Next steps

Phase 1 — renditions (the HDR/SDR case):

1. **Verify the stray-import path end-to-end** (inherited; still
   code-read inference): let a second copy of an owned unit land,
   confirm the second `WatchedFile` appears and the pick is
   insertion-order-arbitrary.
2. **Rendition metadata deriver** — resolution, dynamic range
   (SDR/HDR10/DV/HLG), codec, source tier, file size on `WatchedFile`
   (or a sibling table), recomputable per ADR-057; backfill on boot.
3. **Deterministic pick** — one quality-ranking function; collapse
   `populate_leaf_content_url/1` and `playable_file_path/1` onto it;
   honor a persisted per-item **active** override (nil = highest
   quality). Regression tests pin the ranking.
4. **Manage modal: versions section** — list versions with badges
   (`2160p · HDR10+DV · Remux · 48 GB`), radio-select the active one,
   explicit per-file delete (two-phase, ADR-015), total-disk footprint.
5. **Entity-scoped "grab another version"** — release search from the
   detail page, prefilled query, results annotated against existing
   renditions ("you have this quality already"); the one sanctioned
   bypass of the in-library guard.
6. **Wiki** — Using Media Centaur (versions + manage modal), Searching
   & Downloading (second grabs), Troubleshooting (duplicates story).

Phase 2 — cuts:

7. Edition-marker parsing at import ("Director's Cut", "Extended",
   "Theatrical") → second `PlayableItem` with `name`; ambiguous →
   review. Parser rules test-first per house convention.
8. Cut listing in detail page / playback (per-cut progress rows);
   Manage modal groups renditions under their cut.

Deferred (explicitly out of scope):

* Auto-upgrade policy (offer-as-swap seam exists; separate initiative).
* Swap-time pack mitigation (inherited open question: warn / deselect
  file in client / accept-and-document — in tension with the
  client-hygiene principle, commits `73d716ff` / `31af0920`).
* Per-install rendition preference policy (e.g. "prefer SDR") — add
  only if real usage shows the per-entity override isn't enough
  (language-prefs precedent).

## Completion criteria

* Playback pick is deterministic, quality-ranked, override-able, and
  the two legacy pick paths are collapsed to one (regression-pinned).
* All versions of an entry are visible in the Manage modal with
  rendition badges and sizes; the active version is selectable; an
  unwanted version is deletable through the existing two-phase flow.
* A second version of an owned movie can be grabbed from its detail
  page without leaving the entity context.
* An imported second file is classified rendition-vs-cut, with an
  ambiguity review path; cuts carry independent progress.
* The multi-version and duplicate stories are documented in the wiki.

## Pointers

* Model: [ADR-059](../decisions/architecture/2026-07-12-059-cuts-vs-renditions.md),
  [ADR-047](../decisions/architecture/2026-05-17-047-playable-item-reification.md),
  [ADR-057](../decisions/architecture/2026-06-14-057-derived-data-is-recomputable.md).
* Pick paths: `lib/media_centaur/library.ex` —
  `populate_leaf_content_url/1`, `playable_file_path/1`.
* Import append: `lib/media_centaur/library/inbound.ex` — `link_file/2`.
* Acquisition guards: `lib/media_centaur_web/live/incoming_live.ex` —
  `plan_create`; `lib/media_centaur/release_tracking/wants.ex` —
  `want_candidates/2`.
* Manual grab path: `lib/media_centaur_web/live/incoming_live.ex` —
  `grab_selected`.
* Sibling campaigns: `plan-solver-consolidation` (solver-side dedup,
  shipped), `pursuit-identity-and-lifecycle` (landing-side identity).
* Absorbed: `duplicate-episode-copies` (git history, removed
  2026-07-12).
