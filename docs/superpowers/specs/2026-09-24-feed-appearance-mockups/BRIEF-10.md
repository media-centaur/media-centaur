# Round 10 brief — the ground, the edges, the still

**Date** 2026-09-26. **Starts from** `G-couch-feed` state 1 as shipped in
Phases 1–5 (`Discovery.FeedBand`, `Discovery.PersonCard`, the two-column
Discovery page). **Trigger** the owner's first look at the shipped Feed on
the desk: "what can we do to make this look less… bunches of dark boxes".
Then: "show me a bunch of mockups with a variety of options and parameters.
no false options, everything you show me should be a good idea."

## Diagnosis

On a dark UI the convention is that a surface is lighter than its page;
the glass cards are. The Feed inverted it: every band and every person card
sits on ink at 13% while Discovery's ground is base-100 at 27% under the
blue blob, dimmed only from a third of the way down the viewport. A unit
darker than its ground reads as a hole, and eight holes with 12px corners
and 6px gaps read as a grid of boxes. Inside a band, the text zone is 700 of
the 1236px under a scrim at .93–.97, so more than half of every band is a
flat dark field with a still pasted at its right; the rail's cards are flat
ink around three small posters.

The mockups of rounds 5–9 did not show this because `base.css` mirrored the
app's ground as one radial from 28% to 17%, while the app paints 27% flat
plus two blobs plus `.page-side-dim` — lightest exactly where the first band
and the first card sit. Round 10's "app" ground is the real one, layer for
layer, so the reference cell reproduces the owner's screenshot.

## The knobs

Every direction is G's page under one set of attributes on `<html>`
(`round10.css`), built by `make-round-10`:

| Knob | Values | What it moves |
|---|---|---|
| Page ground | app · dark · ink | today's ground; the same with the dim from the top (≈15%); the ink itself |
| Unit ground | ink · open · glass | the unit's own ink; nothing (the row is the page); one glass panel per column |
| Ink tone | 13 · 16 · 19 | the unit's lightness, the scrim and hover following |
| Edges | cards · sheet | 6px apart with corners; flush in one surface with the column's corners |
| Hairline | on · off | between flush units, across the words, gone over the picture |
| The still | box · wide · full | begins at 700 (536 wide, a 74% slice), at 400 (836, 48%), or at 0 (1236, 32%) |
| Dissolve | 240 · 360 · 480 | the still's mask from its left edge |

The still's extent needs ink under the words, so it is an ink-unit knob;
the hairline needs flush units. The switchboard greys a knob out when the
others make it moot.

## The directions

Six presets, each a distinct answer to the diagnosis, each a good idea:

| | Fixes the inversion by | Page | Unit | Edges | Hair | Still |
|---|---|---|---|---|---|---|
| Q1 Dark sheet | darkening the ground; merging the units | dark | ink | sheet | on | box |
| Q2 Film strip | the page at ink; the picture as the band | ink | ink | sheet | off | wide |
| Q3 Open rows | removing the unit's ground | app | open | sheet | on | box |
| Q4 Glass list | the house panel, lighter than the page | app | glass | sheet | on | box |
| Q5 Matched cards | darkening the ground only | dark | ink | cards | off | box |
| Q6 Dark sheet, wide still | Q1 with Q2's still | dark | ink | sheet | on | wide |

## Rules in play

Couch readability is primary (the 22px floors, text on ≥ .84 ink). The
band's anatomy does not move: tile, poster, three lines, the time, the seat.
UIDR-033 (only Home carries artwork) is not touched — the still is the
band's subject. A darker Discovery ground is a page-scrim variant, the kind
Settings and Status already have (`.page-side-dim-calm`).

## Deliverables

`Q1`–`Q6` pages with `REASONING.md`; `Q-switchboard/index.html` (every knob
live, the state in the address); `Q-switchboard/compare.html` (today and
the six at half size — the 10-foot check); `CRITIQUE-10.md`.
