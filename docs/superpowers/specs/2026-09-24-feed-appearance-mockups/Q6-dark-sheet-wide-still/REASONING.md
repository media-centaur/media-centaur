# Q6 · Dark sheet, wide still — reasoning

**Knobs** ground `dark` · unit `ink` 13% · edges `sheet` · hairline `on` · still `wide` · dissolve 240.

## Style

Q1 and Q2 crossed. Discovery's ground darkened to the ink's tone with the
blobs faint; the columns flush with the column's corners; a hairline
between units across the words, gone over the picture; and the still
beginning under the title's tail (836 wide) so the frame is drawn at a
larger scale — a 48% slice — with a hint of it behind the words. One dark
page, a column of photographs, a rail of people.

## Decisions

* **Q1's page.** The app's ground with the dim from the top keeps the
  blobs and the app's layering; a flat ink page (Q2) loses them.
* **Q1's hairline.** Where two dark stills meet, the reel (Q2) goes soft;
  the hairline keeps the list's rhythm and costs nothing over the picture,
  where it fades out.
* **Q2's still.** The wider frame is what the couch sees: faces at a
  larger scale, the settled crop rule, the words on ≥ .86 ink.

## Requirements

* *Less boxes* — as Q1: the boxes have nothing to show against and the
  units are merged.
* *A good idea* — each part is one of the round's directions; the cross
  takes the strongest part of each and neither's cost.
* *Couch* — the bigger frame is the one gain over Q1; readability is Q1's.

## Trade-offs

Gains: Q2's presence with Q1's page and rhythm. Costs: two changes to the
band's CSS (the box origin and the scrim's stops) on top of Q1's page and
sheet rules; a hint of picture behind the words that the text shadow has to
carry. In the app: the `.page-side-dim` variant, the sheet rules and
hairlines, `--bx: 400px`, and the scrim's stops at 400/700/820/940/1060.
