---
status: accepted
date: 2026-08-31
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
