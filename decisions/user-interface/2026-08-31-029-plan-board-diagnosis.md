---
status: accepted
date: 2026-08-31
---
# The plan board narrates a diagnosis, not a procedure

## Context and Problem Statement

The plan board's body narrated the coverage ladder's internal arithmetic:
a descent panel headline plus one row per rung ("Season packs — covered 1
episode — 21 still missing"), with evidence scattered across banner rows
appended beneath (pack offers, below-preference, gap verdict). For a
1988 sitcom wanted at the 1080p default, where the world offers ~100
releases that are all SD singles, the board reported "Search finished —
21 episodes couldn't be found anywhere" — arithmetically true, false in
spirit, and actionless. Rung attribution also produced nonsense copy
("Season packs covered 1 episode" when a season query surfaced a lone
1080p single). Below-preference availability was counted only for
movies, so the TV story was invisible entirely. Cancelling mid-search
existed only as a "Discard" status flip the running search never
observed.

## Decision Outcome

Chosen option: "verdict-led diagnosis board", because the plan's content
is what the world offers for each wanted episode measured against the
user's terms — and every affordance is either reading that diagnosis or
revising one of its terms.

The body becomes, top to bottom:

1. **Verdict sentence** — one plain-language line generated from a
   closed set of count-proven worlds (UIDR-022 promoted from banner to
   headline; the sole sentence-maker, searching and finished states
   both). Never inferred causes.
2. **Episode grid, enlarged** — each cell renders its unit's outcome
   (kept / available only below preference / nothing / searching) by
   fill and border only; focus/hover captions the episode's best release
   under the grid.
3. **Outcome rows** — the below-preference outcome renders as one
   grouped row however many episodes it covers, carrying the decision:
   **Take lower quality for this show** (implemented copy — "SD" was
   imprecise; the releases are whatever exists below the preference),
   *Show them* when a single unit anchors the row (reusing the
   alternatives panel), and the scope note. A zero-count outcome
   renders no row. Per-episode drill-in for multi-episode rows rides
   the grid cells: each cell is a focusable nav item and the caption
   line under the grid names the focused or hovered episode and its
   best release (landed 2026-09-01; the grid is its own `plan_grid`
   SHELF region between a `plan_head` and a `plan_body` TREE — see
   `docs/input-system.md`, *Overlays with regions*). Cells carry no
   tooltips: a caption a cursor can reach replaces one only a pointer
   could.
4. **Kept releases** — unchanged release rows.
5. **Receipts footnote** — one muted line (searches · indexers ·
   freshness · results · out-of-scope note) that reconciles, with a
   collapsed "How we searched" disclosure holding the rung narrative.
   The descent panel's headline role is retired.

Mid-search, the footer action is **Stop searching** — one press, no
confirmation, effective within one search term, settling the board with
what is known. "Discard" with confirmation remains only for a ready
plan. The word "floor" never appears in user copy.

### Consequences

* Good, because the user's real question — take what exists, hold out,
  or stop — is answered above the fold with the action attached to its
  evidence.
* Good, because verdict, grid, and rows are three renderings of one
  per-unit outcome model, so they cannot contradict each other.
* Good, because the layout scales to multi-season plans (rows total per
  outcome, not per banner).
* Bad, because verdict copy needs a template family per world, extended
  whenever the outcome vocabulary grows.
* Bad, because retiring the descent headline and banner stack touches
  every board view model and its stories in one change.
