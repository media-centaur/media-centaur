# Incoming Page — Design Plan

> **Design-level document.** Describes WHAT the merged page is, not how to build it.
> Visual reference: `mockups/incoming-page/` (open `index.html`; `REASONING.md` carries the
> direction rationale and v1→v2 delta). Decision record:
> `decisions/user-interface/2026-07-11-015-incoming-page.md`. Derive the implementation
> plan from this document when work begins.

## Problem Statement

Upcoming and Downloads are two thin, rarely-visited pages that split one continuous story
at release day and serve one shared intent: growing the collection. Following a single
release from "announced" through "downloading" to "in library" requires page-jumps, and
both pages leave most of their canvas unused.

## Design Objectives

- **Intent-first**: the page exists to add things; the add affordance is the hero, never
  more than one glance away.
- **One legible axis**: arriving → adding → what's coming → what's arriving → what landed,
  as a single downward flow with a strict density gradient (spacious hero → big-art shelf →
  compact operational band → fading ledger). Open sections on the page surface; chrome only
  where operational.
- **Calm that survives busy days**: operational content grows without displacing the hero
  or shelf from first paint, and without turning bands into boxed widgets.
- **Honest degradation**: without acquisition capability the page is a genuine
  forecast-only surface, not a downloads page with holes.

## User-Facing Behavior

- **Page**: "Incoming", Watch nav group, replacing the Upcoming and Downloads nav entries.
  `/upcoming` and `/download` deep links land on the new page.
- **Search hero**: centered omnibox ("What would you like to add?") with two modes —
  search titles to add/track/plan, or search releases directly. Results occupy the space
  below the hero (the shelf recedes); dismissing restores the page. Existing track/plan
  modals are reused as-is.
- **Coming up shelf**: large poster cards in nearness order with progressively explicit
  date labels (Tonight → Tue → Fri Jul 17 → Aug 6). States as shared pill vocabulary:
  armed, in pursuit (with percent), in theaters (watch-only), tracked. Season drops get a
  stacked treatment. Overflow past the shelf cap grows the shelf in place ("Show all N" —
  the same idiom as the ledger's "Show earlier"). After the last card, a dashed horizon
  terminus with a real card's footprint carries the action alone — "Track something".
  (The v1 calendar disclosure was cut during build review: its wayfinding job died with
  the timeline rail, and its marks duplicated the shelf's date labels. A real month view,
  if ever wanted, is its own future design.)
- **In flight band**: draft-plan banner (review / approve), live torrent rows
  (percent, speed, ETA), searching pursuits. An under-pursuit shelf card's pill anchors to
  its torrent row; the row reuses the card's art, title, and pill so the pair reads as two
  zoom levels of one object.
- **Recently landed ledger**: terminal pursuits (landed / failed / cancelled) as open rows
  dissolving into the page floor via a mask fade; "Show earlier" reveals older rows into
  the dissolve; "View all" expands the same section in place into the filtered archive
  (chips + search) — one history surface, no sibling section (merged during build review);
  storage free-space sits as the ledger's ambient foot line, with the escalated per-drive
  cards closing the page under a "Storage" section heading.
- **Acquisition off**: in-flight band and ledger absent; hero copy reframes to tracking;
  release-search mode absent; no badge or caption implies grabbing is possible (armed
  captions become plain dates).

## Acceptance Criteria

- [x] All current Upcoming and Downloads capabilities are reachable from the one page
      (track, plan, approve, cancel, retry, release search, history filters — some behind
      disclosures/modals, none dropped).
- [x] With acquisition unconfigured, the page renders forecast-only and nothing on it
      implies grabbing is possible.
- [x] Empty states stay inviting: nothing tracked → hero + horizon terminus, no dead
      panels; nothing in flight → the band collapses entirely rather than rendering an
      empty box.
- [x] A busy day (8+ torrents, multiple plans) keeps the shelf reachable — the in-flight
      band grows but the page's order and section voice hold.
- [x] An under-pursuit shelf pill navigates to its torrent row; the row identifies itself
      with the same art, title, and pill.
- [x] Keyboard/gamepad navigation traverses hero → shelf → band → ledger as proper nav
      zones (input-system page behavior).
- [x] `/upcoming` and `/download` deep links land users on the new page.

## Anti-patterns

- **Dashboard-widget-grid**: bands reading as stacked panels instead of one page; chrome
  anywhere non-operational.
- **Density inversion**: operational content pushing the hero or shelf out of first paint.
- **Dishonest degradation**: any acquisition-off UI implying grabbing (standard: armed
  captions degrade to plain dates).
- **Redundant empty states / CTA rails**: "nothing here yet" boxes duplicating the hero.
- **Decorative per-item hues**: color stays health/state-only; identity comes from art,
  name, and icon.

## Deferred

- Full-history deep view redesign (existing history UI behind "View all history" is fine
  for v1).
- Orphan/other-downloads presentation (remains a quiet disclosure; revisit later).
- Home-page cross-promotion of the shelf.

## Decisions

- `decisions/user-interface/2026-07-11-015-incoming-page.md` — paradigm choice and page
  structure. Extends 010 (page redistribution) and 014 (media search front door).
