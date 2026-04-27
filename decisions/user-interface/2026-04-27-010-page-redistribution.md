# Page redistribution: Watch / System sidebar groups + dedicated Home, Library, Upcoming, History

- Status: Accepted
- Deciders: Shawn McCool
- Date: 2026-04-27
- Tags: information-architecture, navigation, sidebar, library, home, upcoming, history

## Context and Problem Statement

The pre-refactor `/` (LibraryLive) did three different jobs jammed into one page: a Continue Watching strip, a catalog browse grid, and an Upcoming Releases zone (calendar + tracking + active shows + recent changes). They were switched via a `?zone=` URL param and tabs. The three zones serve three different mental modes — present (resume), atemporal (browse), future (anticipation) — and conflating them on a single page worked against the "Netflix but yours" cinematic feel the project targets.

Two related secondary problems: Watch History existed at `/history` but was hidden from the sidebar nav, and the sidebar mixed cinematic content surfaces (Library) with operator surfaces (Downloads, Review, Status, Settings) in one flat list with no visual distinction.

## Considered Options

1. **Status quo with cosmetic tweaks** — keep the zones, polish the visuals.
2. **Tabs within Library, no new pages** — promote the zones to first-class tabs with deeper styling, but keep them on `/`.
3. **Split into focused pages + sidebar groups (chosen)** — make each mental mode its own page, group sidebar links into Watch and System.

## Decision Outcome

Chosen: option 3 — split into focused pages and group the sidebar.

The new IA:

| Path | Page | Purpose |
|---|---|---|
| `/` | HomeLive | Cinematic landing — hero + Continue Watching + Coming Up This Week + Recently Added + Watched Recently |
| `/library` | LibraryLive | Pure catalog browser (poster grid, filters, sort) |
| `/upcoming` | UpcomingLive | Calendar + tracking + active shows + recent changes |
| `/history` | WatchHistoryLive | Stats + heatmap + activity log + rewatch counts |
| `/download`, `/review`, `/status`, `/settings`, `/console` | unchanged | Operator pages |

The sidebar splits into two visually distinct groups:

- **Watch** (full size, cinematic): Home, Library, Upcoming, History
- **System** (smaller font, dimmer color via `.sidebar-link-system`): Downloads, Review, Status, Settings

History gains rewatch-count badges (`Nx`) on event rows so it's a destination worth visiting, not just a log.

Old URLs are preserved via redirects: `/?zone=upcoming` → `/upcoming`, `/?zone=library` → `/library`, `/?zone=continue` → `/`.

## Why this wins

- **Each page has one mental mode.** No more conflated "what page am I on" feeling when scrolling Library.
- **Home becomes the cinematic surface** — assembled from three contexts, the only assembled page in the app. Every other page is single-purpose.
- **Library becomes pure** — a catalog browser, not a Swiss army knife. 1567 → 601 lines after the strip.
- **Hidden pages get promoted** — Watch History is too good to bury.
- **Operator pages still present** but visually demoted, reinforcing the frontstage/backstage split.

## Consequences

**Good:**

- Cleaner mental model for users; cleaner code for contributors.
- HomeLive can be enriched independently (recommendations, year-in-review widgets, etc.) without touching Library.
- LibraryLive can be optimized for catalog-scale browsing without compromising other surfaces.
- Each page is independently shippable and reversible during the refactor — no big-bang risk.

**Bad:**

- One brand-new page (HomeLive) to maintain — assembles data from Library + ReleaseTracking + WatchHistory.
- Two visual weights for sidebar links — slightly more CSS to maintain (`.sidebar-link` + `.sidebar-link-system`).
- Some intentional code duplication during the migration window: zone-3 logic was first copied into UpcomingLive (Phase 3) before being deleted from LibraryLive (Phase 4). Phase 4 cleaned this up.

**Neutral / future:**

- HomeLive's `load_in_progress` reuses LibraryLive's all-entities-then-filter-in-memory approach — fine at current library sizes; a targeted query would be better at scale.
- HomeLive's `watched_recently` row currently shows title only (no year, no poster) because `WatchHistory.Event` doesn't carry those fields and a per-row Library lookup wasn't pursued. A follow-up could enrich.
- Coming Up This Week badges are uniform (`Scheduled`) until HomeLive subscribes to Acquisition grab statuses.

## Implementation

Done in 4 phases, each independently shippable, fully test-covered:

1. **Phase 1** — `WatchHistory.Rewatch` query module + facade exports + `Nx` badges on `/history` event rows.
2. **Phase 2** — Sidebar Watch/System CSS + HTML restructure + History promoted to nav.
3. **Phase 3** — `UpcomingLive` extracted to `/upcoming` with its own subscription wiring; `/?zone=upcoming` redirect added.
4. **Phase 4** — 4 new row components (HeroCard, ContinueWatchingRow, ComingUpRow, PosterRow) + `HomeLive.Logic` pure helpers + new Library/ReleaseTracking facade functions + LibraryLive zone strip + cutover (`/` → HomeLive, `/library` → LibraryLive) + sidebar Home link.

Visual reference and design narrative: `mockups/page-redistribution/` and `mockups/page-redistribution/REASONING.md`. Implementation plan: `docs/plans/2026-04-27-page-redistribution.md`.

## Related

- ADR-006 (Library zone architecture) — superseded for `/`. The zone concept lives on inside `/library` for type tabs (All / Movies / TV / etc.) but no longer for cross-mode switching.
- ADR-030 (LiveView logic extraction) — followed throughout: `HomeLive.Logic`, `WatchHistoryLive`'s rewatch lookup helper, etc.
- ADR-029 (Data decoupling / Boundary) — HomeLive crosses three contexts via their facades; declared deps on `MediaCentarrWeb`'s boundary.
