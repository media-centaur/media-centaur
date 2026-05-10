---
status: in-progress
started: 2026-04-27
last_updated: 2026-05-10
---
# Page redistribution — Watch / System sidebar split

## Goal

Decompose the current `/` (`LibraryLive`) — which today does
three different jobs (Continue Watching + Browse + Upcoming) —
into one mental mode per page, organised in two visually
distinct sidebar groups:

* **Watch** (frontstage, cinematic): **Home** (`/`, new, hero +
  rails), **Library** (`/library`, browse only), **Upcoming**
  (`/upcoming`, promoted from a zone), **History** (`/history`,
  promoted from hidden).
* **System** (backstage, demoted styling): **Downloads**,
  **Review**, **Status**, **Settings** — functionally
  unchanged, visually quieter.

The end-state feel is "Netflix but yours" — each page does one
thing, the sidebar separates *what you're watching* from *what
you're operating*.

## Status

Active IA refactor. Home page exists and is the new `/`
(ContinueWatching projection lives there per ADR-041). Sidebar
grouping not yet applied. Library / Upcoming / History split
not yet executed. Mockups exist; phased rollout is the agreed
shape but phases aren't enumerated in this file yet.

> **Reconciliation needed on next pickup.** The seed memory
> referenced `mockups/page-redistribution/` and a planned doc
> at `docs/superpowers/plans/2026-04-27-page-redistribution.md`
> — neither exists. Current mockup artifacts live under
> `mockups/home-redesign/` (three numbered variants:
> `1-cinematic-compression`, `2-editorial-billboard`,
> `3-netflix-fluid`). First action when resuming: walk the
> mockups + current `LibraryLive` / `HomeLive` to confirm what
> shipped vs. what's still ahead, and update Status +
> Workstreams.

## Decisions made

Append-only.

* `2026-04-27` — **Two sidebar groups: Watch (frontstage) +
  System (backstage).** Visual styling differentiates them so
  the operator-vs-viewer modes are immediately legible.
* `2026-04-27` — **Each Watch page owns one mental mode.**
  Browse, anticipation, completion-history, and
  resume-watching are not co-located.
* `2026-04-27` — **History gets re-watch surfacing as a
  baseline.** "You've watched X N times" — without a hook like
  this, History isn't magnetic enough to earn a primary nav
  slot.
* `2026-04-27` — **Phased rollout, each phase independently
  shippable.** No big-bang rewrite.
* `2026-05-10` — Home (`/`) shipped with ContinueWatching
  projection + hero + recently-added + coming-up rails (per
  desktop-rearchitecture campaign Workstream A). Sidebar
  grouping and the Library / Upcoming / History promotions
  haven't followed yet.

## Workstreams

Phases below are inferred from the goal — re-derive against the
current code on next pickup and rewrite this section if the
shape has shifted.

### A. Sidebar grouping

* [ ] Visual treatment: Watch group (cinematic) vs System
  group (demoted). Designed in storybook first (per the
  storybook-first feedback rule).
* [ ] Sidebar component refactor to render two grouped
  sections.
* [ ] Route ordering and active-state styling per group.

### B. Library page narrowing (browse-only)

* [ ] Remove the Continue Watching zone from `/library`
  (Home owns it now).
* [ ] Remove the Upcoming zone from `/library` (moves to
  `/upcoming`).
* [ ] Library becomes "browse the catalog" — single mental
  mode.

### C. Upcoming page promotion

* [ ] New `/upcoming` route + LiveView.
* [ ] Lift the existing Upcoming zone view into a top-level
  page treatment.
* [ ] Pillar-2 projection (per ADR-041) for the upcoming
  feed if it isn't already covered by the desktop-rearchitecture
  Workstream A `ReleaseTracking.Views.ComingUp`.

### D. History page promotion + re-watch surfacing

* [ ] New `/history` route + LiveView.
* [ ] Re-watch surfacing baseline: count of times each entity
  has been watched, foregrounded so the page is magnetic.
* [ ] Determine source of truth (existing `WatchHistory`
  context? new aggregate?) and whether a Pillar-2 projection
  is warranted.

### E. Storybook first

Every visual change above is designed in Phoenix Storybook
*before* it lands in the app — the story is the acceptance
criterion (per the storybook-first feedback rule). Workstream
A's sidebar treatment and Workstream D's re-watch baseline
deserve dedicated stories.

## Completion criteria

* `/`, `/library`, `/upcoming`, `/history` each render their
  intended single mental mode.
* Sidebar visibly distinguishes Watch and System groups.
* History re-watch surfacing is visible by default, not
  opt-in.
* Mockups directory and corresponding stories agree with the
  shipped UI.
* The Library page no longer hosts Continue Watching or
  Upcoming zones.

## Out of scope

* Projections / data layer changes — those live under the
  desktop-rearchitecture campaign (Workstream A), even when
  this campaign needs a new view (`ComingUp`, history reads).
* Component contracts — separate campaign.
* Settings, Downloads, Review, Status changes — unchanged
  functionally; only their sidebar styling treatment is in
  scope.

## Pointers

* `mockups/home-redesign/` — three exploration variants for
  Home (`1-cinematic-compression`, `2-editorial-billboard`,
  `3-netflix-fluid`). Memory's earlier
  `mockups/page-redistribution/` pointer is stale.
* `lib/media_centarr_web/live/home_live.ex` — current Home,
  shipped with ContinueWatching projection.
* `lib/media_centarr_web/live/library_live.ex` — current
  multi-mode Library page being decomposed.
* `lib/media_centarr_web/components/sidebar*.ex` — sidebar
  component(s) for Workstream A.
* [Desktop-rearchitecture campaign](desktop-rearchitecture.md)
  — the data-layer counterpart; this campaign should
  coordinate with its Workstream A.
* The user-local memory entry
  (`project-page-redistribution.md`) was the seed for this
  file. Treat the campaign file as the source of truth going
  forward; the memory entry is supporting context.
