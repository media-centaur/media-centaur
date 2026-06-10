---
status: accepted
date: 2026-06-10
---
# Media-search front door — omnibox, coverage language, and imagery discipline

## Context and Problem Statement

Media search (campaign: `campaigns/media-search-tmdb-acquisition.md`) is
the primary acquisition path, but `/download` grew around the
release-name search: a utilitarian text page with the search box at the
bottom. The Phase 3 backend (targeting → durable draft plan → planner →
commit) shipped with no UI. Four surfaces needed design decisions: the
page structure, the targeting picker, the live planning view, and the
approval step — plus where the demoted "naked search" lives and how
rich the page's visual identity should be.

Design session 2026-06-10; four HTML mockups compared
(`~/.agent/mockups/media-search-front-door/`, session artifacts — this
record is the spec).

## Decision Outcome

### 1. The omnibox is the page — one search surface, two modes

`/download` opens with a hero search field ("What do you want to
watch?") that searches TMDB as you type. The naked release search is a
**mode flip of the same box** — flipping swaps the TMDB dropdown for
today's release-search session UI below the hero. Rejected: zone tabs
(buries live acquisition status behind a navigation flip, killing the
watch-it-happen value) and a CTA-button-into-modal (a button is not a
door; media search must *feel* primary).

### 2. The plan flow is one continuous URL-driven modal

Picking a TMDB title opens the plan flow as a modal driven by a URL
param (the `?selected=` pursuit-modal pattern): targeting picker →
live coverage board → approval footer, one flowing surface — **no
wizard step-dots**. The durable draft + URL makes every stage
refresh-safe; closing mid-plan leaves a resumable draft card on the
page. Movies skip the picker for a mini-confirm (two clicks to a
plan).

Picker rules: quick-action presets ("Everything aired" default,
"Continue from my library", "Latest season") write into tri-state
season checkboxes — presets are *presets*, checkbox state is the only
source of truth. In-library episodes render greyed with an "In
library" chip (subtractions shown, never hidden — campaign decision);
unaired seasons render inert. Footer: quality range pill, "grab
future" opt-in, "Plan N episodes" with a live count.

### 3. One coverage language: unit cells, everywhere

The planning board is **unit-grid-first**: episode cells in season
rows. Cell vocabulary — dashed/pulsing = searching, filled = assigned,
cells *fused into a single capsule* = one pack covers them
(consolidation made visible), amber-hollow = unfound gap, grey-check =
in library. Chosen releases list beneath the grid (scope chip,
monospace release name, quality/seeders/size, swap + exclude); cell ↔
release row highlight on hover/selection. A live activity ticker
(searches, corpus vs live) replaces any spinner — **planning must
visibly work**. The approval step is the board's footer (coverage
summary + Discard + "Approve & grab N releases"), not a separate
screen; gaps render as an explicit warning row with a disabled "track
these later" slot (wired in campaign Phase 4).

The same cell vocabulary appears as a **segmented unit-progress row**
on composite pursuit cards (landed / downloading / gap squares) and in
the pursuit modal's existing UnitBoard — plan, card, and drill-down
speak one language, so approving a plan reads as the board carrying
over into the pursuit.

### 4. Imagery is identity — and it is earned, not decorative

Title-doored cards (draft plans, TMDB-door pursuits) get a
**backdrop + logo banner treatment**; query-door pursuits stay plain
text rows with a small "release search" chip. The contrast is the
design: imagery means *a title you chose*, plain text means *a raw
query you typed*. Discipline that keeps it from becoming a poster
wall:

* **Scrim rule**: backdrops are heavily desaturated and scrimmed
  (strong left-to-right dark gradient); semantic status colors must
  remain the brightest accents on every card ("color is signal"
  survives imagery).
* **Banner heights** (~120–130px), never hero heights, so stacked
  pursuits read as layers.
* **Graceful fallback**: when no local artwork exists (title not in
  the library), cards render the scrimmed-gradient + styled-logotype
  treatment — no hot-linking TMDB images from the downloads page in
  v1; real `backdrop_path`/logo plumbing for non-library titles is a
  follow-up.

Text-over-imagery follows [UIDR-011]; modal dismissal follows
[UIDR-013]; buttons/badges per [UIDR-003]/[UIDR-002].

### Consequences

* Good, because the page finally states its purpose — intent-first
  acquisition — and the naked search survives intact as a mode, not a
  casualty.
* Good, because one cell vocabulary spans plan → card → drill-down;
  the user learns it once.
* Good, because every stage is refresh-safe by construction (durable
  draft + URL-driven modal).
* Bad, because the omnibox's dual mode adds one learnable control
  (mitigated: the flip is labeled, and release mode is exactly the old
  UI).
* Bad, because synthetic-fallback banners (no artwork) vary in
  quality with the title's name length/styling; acceptable for v1.

[UIDR-002]: 2026-03-03-002-badge-style-convention.md
[UIDR-003]: 2026-03-03-003-button-style-convention.md
[UIDR-011]: 2026-05-12-011-text-on-imagery.md
[UIDR-013]: 2026-06-08-013-modal-dismissal-modes.md
