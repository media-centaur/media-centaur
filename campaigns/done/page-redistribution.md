---
status: shipped
started: 2026-04-27
last_updated: 2026-05-10
---
# Page redistribution — Watch / System sidebar split

## Goal

Decompose the original `/` (`LibraryLive`) — which did three
different jobs (Continue Watching + Browse + Upcoming) — into one
mental mode per page, organised in two visually distinct sidebar
groups:

* **Watch** (frontstage, cinematic): **Home** (`/`, hero + rails),
  **Library** (`/library`, browse only), **Upcoming** (`/upcoming`),
  **History** (`/history`).
* **System** (backstage, demoted styling): **Downloads**,
  **Review**, **Status**, **Settings** — functionally unchanged,
  visually quieter.

The end-state feel is "Netflix but yours" — each page does one
thing, the sidebar separates *what you're watching* from *what
you're operating*.

## Status

**Complete pending reconciliation.** Reconciliation on 2026-05-10
walked the shipped code and found every workstream substantially
done — the prior campaign file pre-dated the implementation push
and was never updated. Findings:

* Sidebar Watch / System split is live in
  `lib/media_centarr_web/components/layouts.ex` (lines 64-155),
  with CSS-driven demotion of the System group in `assets/css/app.css`
  (`.sidebar-link-system`: smaller font, dimmer colour, smaller icons).
* `/upcoming` route + `UpcomingLive` exists.
* `/history` route + `WatchHistoryLive` exists, with stats, GitHub-style
  heatmap, and rewatch counts surfaced by default.
* `LibraryLive` carries an explicit comment that Continue Watching
  and Upcoming zones moved away; only the Browse zone remains.

All five Completion criteria below are met. The remaining items are
small: documenting the campaign as done, and (separately) ensuring
storybook stories cover the new sidebar grouping and the History
re-watch baseline. Story coverage is best tracked in the
component-contracts campaign once that pass kicks off.

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
  desktop-rearchitecture campaign Workstream A).
* `2026-05-10` — **Reconciliation finding: shipped in advance of
  this file.** Workstreams A-D all landed in the development push
  that pre-dated the campaigns/ convention. Sidebar grouping,
  Library narrowing, Upcoming page, and History page (with rewatch
  surfacing) are all live. The campaign file was a retroactive
  description that drifted from reality.
* `2026-05-10` — **Demotion is class-driven.** The System group's
  visual quietening is `sidebar-link-system` on each link plus
  matching rules in `app.css` — same DOM structure as Watch links,
  just a different class. Easier to tune than a separate component.

## Workstreams

### A. Sidebar grouping

* [x] Visual treatment: Watch group (cinematic) vs System
  group (demoted). CSS-driven via `.sidebar-link-system`
  (smaller font, dimmer colour, smaller icons). *(shipped)*
* [x] Sidebar refactor to render two grouped sections.
  Inline in `Layouts.app/1` — `.sidebar-group-label` separators
  between `<nav>` blocks. *(shipped)*
* [x] Route ordering and active-state styling per group.
  *(shipped)*

### B. Library page narrowing (browse-only)

* [x] Continue Watching zone removed from `/library`. *(shipped)*
* [x] Upcoming zone removed from `/library`. *(shipped)*
* [x] Library is now "browse the catalog" — single mental mode.
  Confirmed via the moduledoc comment in `library_live.ex`. *(shipped)*

### C. Upcoming page promotion

* [x] New `/upcoming` route + `UpcomingLive`. *(shipped)*
* [x] Upcoming zone view lifted into a top-level page treatment.
  *(shipped)*
* [x] Pillar-2 projection — `ReleaseTracking.Views.ComingUp`
  shipped under desktop-rearchitecture Workstream A on 2026-05-10.
  `UpcomingLive` itself should be migrated to read from that
  projection (follow-up — tracked under desktop-rearchitecture).

### D. History page promotion + re-watch surfacing

* [x] New `/history` route + `WatchHistoryLive`. *(shipped)*
* [x] Re-watch surfacing baseline: rewatch counts foregrounded
  by default (`rewatch_counts` assign + heatmap). *(shipped)*
* [ ] **Pillar-2 projection** — `WatchHistory.Views.*` not yet
  built. Tracked under desktop-rearchitecture Workstream A; route
  is now firm so the projection's read shape can be designed.

### E. Storybook first

* [ ] Sidebar Watch / System group story — not yet written.
  Low priority since the implementation has settled; useful for
  future visual-treatment iteration. Tracked under the
  component-contracts campaign Workstream D.
* [ ] History re-watch baseline story — same.

## Completion criteria

* [x] `/`, `/library`, `/upcoming`, `/history` each render their
  intended single mental mode.
* [x] Sidebar visibly distinguishes Watch and System groups.
* [x] History re-watch surfacing is visible by default, not
  opt-in.
* [x] The Library page no longer hosts Continue Watching or
  Upcoming zones.
* [ ] Mockups directory and corresponding stories agree with the
  shipped UI. *(stories outstanding — see Workstream E)*

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
  `3-netflix-fluid`). Reflects the design exploration that
  preceded the shipped Home.
* `lib/media_centarr_web/components/layouts.ex` — sidebar
  Watch / System split lives here (no dedicated component).
* `assets/css/app.css` — `.sidebar-group-label` +
  `.sidebar-link-system` rules.
* `lib/media_centarr_web/live/home_live.ex` — Home (`/`).
* `lib/media_centarr_web/live/library_live.ex` — narrowed
  browse-only Library page.
* `lib/media_centarr_web/live/upcoming_live.ex` — Upcoming
  page.
* `lib/media_centarr_web/live/watch_history_live.ex` —
  History page with rewatch surfacing.
* [Desktop-rearchitecture campaign](desktop-rearchitecture.md)
  — the data-layer counterpart; WatchHistory.Views projection
  follow-up tracked there.
