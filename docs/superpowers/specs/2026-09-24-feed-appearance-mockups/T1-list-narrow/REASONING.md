# T1 · List surface, 1500 — reasoning

**Knobs** surface `list` · width `narrow` (1500: feed 916, rail 560) · poster 100 · logo none.

## Style

The Feed as the rest of the app draws a list. One inset glass container
per column, a hairline between rows, the app's own ground behind. Each row
is the settled anatomy — tile, poster at 100×150, who did what, the title
and year, the review, the seat — at the couch floors, with the time at the
row's right edge. No still, no scrim, no dissolve. The rail is the same
container with the person cards as rows.

## Decisions

* **The list surface, not the sheet.** "Like what we have already in the
  app" is Watch History's container. Its inset tone sits close to the
  ground, so it is a surface without being a box; its hairlines give the
  list its rhythm.
* **1500, not 1820 or 1280.** At 1820 the row is words and a time with
  ink between; at 1280 the feed is 776 and reviews wrap to three lines.
  916 holds a two-line review at a reading measure with the time at the
  edge.
* **The poster at 100.** The settled size; it reads from the couch and it
  is the row's one picture.
* **206.** What the words need; the poster fits inside it with 28px above
  and below.

## Requirements

* *No backdrop* — none; the crop machinery goes with it.
* *Like the app* — the app's list idiom, unchanged but for scale.
* *Narrower columns* — 1500.

## Trade-offs

Gains: the calmest Feed of the campaign; nothing to learn; the boxes gone
because the container is the app's own; the one picture is the poster,
which needs no crop. Costs: the Feed stops being a cinematic page — the
"holy crap" bar of round 4 is set aside, deliberately; the poster's
printed title still sits beside the typed one; 320px of the 1820 content
width goes unused at the right. In the app: `FeedBand` loses the backdrop,
scrim and box; the columns take `glass-inset` and hairlines; Discovery's
container narrows to 1500; `offset_crop?` and the adjacency pass are
deleted.
