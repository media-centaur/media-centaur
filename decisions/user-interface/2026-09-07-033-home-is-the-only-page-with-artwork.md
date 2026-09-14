---
status: accepted
date: 2026-09-07
---
# Home is the only page that carries artwork

Supersedes the Library and Incoming halves of UIDR-032.

## Context and Problem Statement

Home's backdrop is the artwork of its hero, the title the page offers. Library and Incoming had no hero: they showed a band of some other title's backdrop, picked by rotation, as decoration, with a slot allocator, two preference toggles, extra scrim ramps, and a launch warmup decoding three 4K masters to support it.

## Decision Outcome

1. `.page-backdrop` on Home is the app's one page-artwork surface, with the UIDR-032 canvas and a single cache slot.
2. Every other page carries `.page-side-dim` only, the subject-free scrim that gives the shell depth, or `.page-side-dim-calm` where the standard ramp reads as a band (Settings, Status, Incoming).
3. `.page-atmosphere`, `.page-side-dim-high`, both backdrop preferences and their toggles are removed; hero selection is `HomeLive.Logic.select_hero/2`.

Artwork on a page means "this is what the page is about". One rule.

### Consequences

* Installs that had the bands lose them with no way back; re-introducing the feature means re-introducing the decision.
