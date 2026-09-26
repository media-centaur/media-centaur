# R1 · Backdrop only — reasoning

**Knobs** logo `none` · still `wide` · on Q6's page (ground `dark`, `sheet`, hairline `on`).

## Style

Q6 with the poster taken out and nothing put in. The words start at the
tile's right (x = 92) and gain 118px of measure, so a review that wrapped
to two lines often fits one. The typed title stays line 2 at 28px with the
year. One picture per band. The band stays 224.

## Decisions

* **Subtract first.** The owner is not sure the poster is the irritation.
  This page isolates the variable: if the column is calmer with the poster
  gone and nothing added, the poster was the noise.
* **Nothing moves up.** The three lines keep their sizes and positions
  apart from the left edge, so this is the column's floor: every logo
  direction falls back to it for a title without a logo, and a column of
  fallbacks must still be a good page.
* **Wide still.** With the poster gone the still is the band's only
  picture; it takes round 10's wider box.

## Requirements

* *Poster and backdrop may be the irritation* — the two-pictures-per-band
  problem is gone by construction; the title is stated once.
* *A good idea* — no new element, no new fallback, no height change.

## Trade-offs

Gains: one picture, one title, more measure, the least change. Costs: the
band's left third is emptier than before on a band without a review ("Cleo
wants to watch / Sintel" is two lines in 224px), and the colour accent the
poster gave a dark row is gone; the still has to carry it. In the app:
delete the poster `<img>` and its empty slot from `FeedBand`, `--x-body`
to 92.
