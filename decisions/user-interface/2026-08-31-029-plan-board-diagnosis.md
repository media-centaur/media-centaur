---
status: accepted
date: 2026-08-31
amended: 2026-11-06
---
# The plan board narrates a diagnosis, not a procedure

## Context and Problem Statement

The board narrated the coverage ladder's arithmetic: a descent headline, a row per rung, evidence in banners beneath. For an SD-only title against a 1080p default it said episodes "couldn't be found anywhere": true in arithmetic, actionless. Discarding mid-run never stopped the search.

## Decision Outcome

Every affordance reads the per-unit diagnosis (ADR-063) or revises a term. Top to bottom:

1. **Verdict sentence** — one line from the closed set of count-proven worlds (UIDR-022), the sole sentence-maker.
2. **Episode grid** — each cell renders its unit's outcome (kept, below preference, nothing, searching) by fill and border, as nav items in a `plan_grid` region; a caption under the grid names the focused episode's best release.
3. **Outcome rows** — below preference is one grouped row however many episodes it covers, carrying *Take lower quality for this show* and *Show them* when one unit anchors it. Zero-count outcomes render no row.
4. **Kept releases** — unchanged.
5. **Receipts footnote** — one muted line (searches · indexers · freshness · results) with a collapsed *How we searched* disclosure holding the rung narrative.

Mid-search the footer action is **Stop searching**: one press, no confirmation, effective within one search term. *Discard* with confirmation remains only for a ready plan. "Floor" never appears in user copy.

### Consequences

* Verdict copy needs a template per world.

**Amendment 2026-11-06 (campaign `plan-modal.md`, M3).** The board is a
**manifest**: one list of lines, each a release with the episode cells it
covers, or a group of cells sharing one outcome — searching, lower quality
only, not found, a pack offer, dropped — with that outcome's decision at
the line's end. Every episode is drawn once, inside the line that
explains it; the separate episode grid (§2) and the release list (§4) are
gone, and so is the caption line: a cell's tip is its episode label
through the app tooltip, which did not exist when §2 forbade per-cell
tooltips. The verdict (§1) moves into the frame's pinned block, one
treatment for every state (clean, planning, the gap worlds, committed),
coloured only when something is missing; the outcome rows (§3) are lines
of the same list, and a coloured edge marks only a line that carries a
decision. The receipts (§5) are always shown — *How we searched* is a
heading over the step rows, with the latest search line above them while
the plan is still planning — never a disclosure. The acts live in the
frame's foot (UIDR-021 as amended the same day). The view model is
`ViewModels.PlanBoard.lines`, built by the pure `Plans.Board.assemble/2`;
its summaries are functions of the lines.
