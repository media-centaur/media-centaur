# Round 13 brief — no backdrop: the poster row in narrower columns

**Date** 2026-09-26. **Starts from** G's row anatomy with the still removed,
on the grounds of rounds 10–12. **Trigger** the owner: "i'm thinking maybe
i don't want the backdrop on there at all and for us to go with something
more like what we have already in the app and maybe just reduce the size of
those columns a bit to counter".

## What "what we have already in the app" is

The list surface: one inset glass container per column with a hairline
between rows, on the app's ground — Watch History's idiom, and the shape
the Feed had before Phase 4 (`FeedEntryRow`: poster, three lines, the time
column, the seat). The campaign's glossary names it. Round 13 draws that
row at the couch floors: the 100×150 poster, 22px words, the 28px title,
the time at the row's edge, the seat at the poster's foot. The still and
its scrim are gone, and with them the crop rule, the adjacency offset, the
mask and the dissolve.

## "Reduce the size of those columns"

Without the still, a 1236px row is words at the left and a time at the
right with ink between. The width comes in:

| | Content | Feed | Rail |
|---|---|---|---|
| full | 1820 | 1236 | 560 |
| narrow | 1500 | 916 | 560 |
| container | 1280 | 776 | 480 |

The 1280 container is the app's own (`max-w-7xl`, left-aligned); the rail's
person card fits 480 without change (three 96px posters and their gaps).
The rail never folds in this round; the fold rule is Phase 5's and
unchanged.

## The knobs

In `round13.css`, built by `make-round-13` on round 11's markup with the
poster kept:

| Knob | Values | What it moves |
|---|---|---|
| Content width | full · narrow · container | the table above |
| Surface | list · sheet · open | the inset container on the app's ground; Q6's dark flush sheet; bare rows on the page |
| Poster | 100 · 80 | ×1.5 tall; the row stays 206 either way, since the words set it |
| The logo | none · headline | round 11's headline in place of the typed title, without a picture |

The row is 206: 20px pads, line 1 at 30, the title at 36, two review lines
at 60, the 32px seat. It cannot go lower at the couch floors without
losing a review line or moving the seat.

## The directions

| | Surface | Width | Poster |
|---|---|---|---|
| T1 List surface, 1500 | list | narrow | 100 |
| T2 List surface, the 1280 container | list | container | 80 |
| T3 Dark sheet, 1500 | sheet | narrow | 100 |
| T4 Open rows, 1500 | open | narrow | 100 |

**Added on the owner's notes** ("for the friends posters, there's the 3
icons in the heading part.. i want those centered over the poster. are we
sure that the circle with the name letter in it should be centered and not
aligned near the top of the row like it is for friends? So far I think i
like t4 the most"): two knobs — `acts` (slots · centred) and `align`
(centre · top) — and **T5**, T4 with both applied.

## Deliverables

`T1`–`T4` pages with `REASONING.md`; `Q-row-switchboard/index.html`;
`Q-row-switchboard/compare.html` (S5 beside the four); `CRITIQUE-13.md`.
