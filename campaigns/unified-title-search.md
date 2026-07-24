---
status: phase-1-in-progress
started: 2026-07-25
last_updated: 2026-07-25
---
# Unified title search (acquire + track from one surface)

## Goal

One TMDB "fancy search" that serves **both** acquiring and tracking.
Today there are two search UIs — the omnibox (which only knows how to
*acquire*: pick → plan/grab) and the Track modal (which only knows how
to *track*) — even though both already call the same search function
underneath. Collapse them into one surface where a picked title offers
a **smart action**: acquire when there's a grabbable release, track when
there isn't, with the other available as a quiet override. The raw
indexer/"search by file" search stays separate (it's a different backend
and a different intent). This removes a whole duplicate UI, one
redundant front door, and the dead-end where planning an unreleased
movie churns and finds nothing.

## Status

**Planning — no code written yet.** The search *backend* is already
unified (`ReleaseTracking.search_tmdb/1`); only the UI wrapper is
duplicated. The prerequisite availability signal shipped this session:
canonical movie-year derivation (`TMDB.Mapper.canonical_release_date/1`
+ `us_typed_release_dates/1`, commit `6b3aaf27`). Rollout is two phases:
Phase 1 = design-free de-duplication (below), Phase 2 = the smart action
+ retiring the Track modal + a unified TV surface (open questions below).

## Decisions made

* `2026-07-25` — Unify the two TMDB search UIs into one. The omnibox is
  the single title-search surface; a picked result can both acquire and
  track. (this discussion)
* `2026-07-25` — The primary action is a **smart** action — acquire when
  a release is grabbable, track when not, with the other as a quiet
  override — **not** two co-equal explicit buttons. (owner preference)
* `2026-07-25` — Keep the raw indexer / "search by file" search separate.
  It's already the omnibox's `:release` mode (Prowlarr backend), distinct
  from the TMDB `/search/multi` flow. Nothing to change there.
* `2026-07-25` — **Two-phase rollout.** Phase 1 is the design-free
  de-duplication (one result struct, one rendering, one build) with **no
  behavior change** and the TV pickers untouched. Phase 2 is the feature
  (smart action, retire Track modal, unified TV surface). Splitting this
  way keeps every intermediate state shippable.
* `2026-07-25` — Prerequisite shipped: canonical movie-year derivation
  (commit `6b3aaf27`) — the availability signal the smart action reads.
* `2026-07-25` — **Struct home settled (open question 7): context.** The
  unified struct is `MediaCentaur.ReleaseTracking.TitleResult`, returned
  directly by `search_tmdb/1` — normalization happens once, in the
  context; the web layer stops re-structifying. Named `TitleResult`
  (not `SearchResult`) because `MediaCentaur.Search.SearchResult` is the
  Prowlarr *release* result, and title-vs-release is this campaign's
  vocabulary split. Boolean field is `tracked?` (idiomatic; replaces
  `already_tracked`).
* `2026-07-25` — Dropped the dead `in_library?` field from the omnibox
  result struct — it was never set and never read. Phase 2 reintroduces
  it when the smart action actually computes it.
* `2026-07-25` — The shared rendering unit is the **identity summary**
  (poster thumb + title + type badge + year), extracted as
  `title_result_summary/1`. The row containers stay per-surface: their
  click semantics genuinely differ (whole-row pick vs. Track button +
  inline pickers), and Phase 2 deletes the modal wrapper anyway.
  Summary adopts the omnibox's styling (the surviving surface),
  including eager image loading per ADR-012.

## Next steps

### Phase 1 — Consolidate the surface (cleanup, mostly deletion, no behavior change)

1. **Merge the two result structs** — `MediaOmnibox.Result`
   (`media_omnibox.ex:32`) and `TrackModal.SearchResult`
   (`track_modal.ex:32`) are the same fields (`tmdb_id, media_type,
   name, year, poster_path, tracked?/already_tracked, in_library?`).
   Collapse to one shared view-model.
2. **One result-row rendering** component used by both the omnibox
   dropdown (`media_dropdown/1`, `media_omnibox.ex:282`) and the Track
   modal results list (`track_modal.ex:253-320`).
3. **One result-build/normalization** from the `search_tmdb/1` maps
   (currently structified twice: `incoming_live.ex:2086-2093` and
   `:1962`).
4. Leave both entry points and the TV pickers exactly as they are —
   Phase 1 must not change what any pick does.

### Phase 2 — The feature (see open questions before building)

5. **Smart acquire/track action** on the picked result: read the
   availability signals and pick the primary action, override quiet.
6. **Retire the Track modal** (input, struct, handlers) and re-point its
   only entry — the shelf "Track something" card (`shelf.ex`) — to open
   the omnibox in media mode.
7. **Unified TV surface** — host both acquire-targeting (which episodes /
   season packs) and track-scope (from S_E onward) in one place. This is
   the hardest part and gates most of the open questions.

## Open design questions (defer to the Phase 2 session)

1. **What counts as "no acquirable release yet"** (the smart-action
   trigger)? Candidates: no digital/physical release date on-or-before
   today (reuses `acquirable_release_type?` — leaning this way) / TMDB
   `status != :released` / `canonical_release_date` nil-or-future. Each
   treats "theatrically out, no home release" differently.
2. **TV targeting vs. track-scope** — can one surface express both
   "grab these episodes/packs now" and "track from here onward"? This is
   the crux of Phase 2.
3. **Movie override when unreleased** — is "Plan anyway" offered (for
   cams/early rips) or hidden when the smart default is Track?
4. **Acquire + track together?** — does grabbing a release also enable
   tracking (grab now, keep watching for upgrades), or is it strictly one
   action at a time?
5. **Post-action feedback** — what "Track" confirms and where it lands;
   reuse the existing track feedback or design new.
6. **Already-in-library / already-tracked** result states — how the smart
   action reflects them (`in_library?`, `tracked?` are already on the
   struct).
7. **Result-struct home** — web view-model vs. a context struct
   (Phase 1 will settle this in passing).

## Completion criteria

* One TMDB search surface (the omnibox). The Track modal is gone; its
  "Track something" entry opens the omnibox.
* Picking a title offers a smart primary action — acquire when grabbable,
  track when not — with the other as an override.
* Both movies and TV are handled in the unified surface.
* No duplicate result struct, result rendering, or search dispatch
  remains.
* The raw indexer / "search by file" search is unchanged and still
  separate.

## Pointers

**Shared search backend (already unified):**
`ReleaseTracking.search_tmdb/1` → `ReleaseTracking.Acquisition.search_tmdb/1`
(`acquisition.ex:32-48`) → `TMDB.Client.search_multi/1`.

**Omnibox (acquire path):** `components/acquisition/media_omnibox.ex`;
`omnibox_change` (`incoming_live.ex:1300`), async at `:1319`; pick
`omnibox_pick` (`:1340`) → `?plan=new` → plan modal `:targeting`(TV) /
`:movie_confirm`(movie) (`plan_modal.ex`); Prowlarr-absent fallback
`track_picked_result` (`:1349`).

**Track modal (track path):** `components/track_modal.ex`, rendered
`incoming_live.ex:773`, opened by `open_track_modal` (`:1460`); own
search `track_search` (`:1495`) → `{:do_track_search}` (`:1960`); select
`select_search_result` (`:1525`) — TV sets `ScopeItem` picker then
`confirm_track` (`:1558`), movie tracks immediately (`:1537`);
`track_suggestion` (`:1501`).

**Tracking plumbing (already movie-capable):**
`ReleaseTracking.Acquisition.track_from_search/2` (`acquisition.ex:87`,
movie branch `:152`); `track_item/1` (`release_tracking.ex:58`);
`Item.create_changeset` requires `[:tmdb_id, :media_type, :name]`
(`item.ex:84`).

**Availability signals (for the smart action):**
`TMDB.Mapper.movie_attrs` → `status` + `date_published`;
`Mapper.us_typed_release_dates/1` / `canonical_release_date/1` (commit
`6b3aaf27`); `Release.released?/2` (`release.ex:59`, air_date ≤ today);
`acquirable_release_type?` (digital/physical).

**Keep-separate raw search:** `MediaCentaur.Acquisition.search/2`
(`acquisition.ex:244`) → `Search.Prowlarr`; UI is the omnibox `:release`
mode (`media_omnibox.ex:194`, `search.ex:28`, `incoming_live.ex:835`).

**Convention:** [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
(campaigns). This file is removed on completion — git history is the archive.
