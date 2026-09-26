# R3 · Title card — reasoning

**Knobs** logo `card` · placement `corner` · logo height 72 · mix `some` · still `wide` · on Q6's page.

## Style

The picture carries the title. The words on the ink are who did what and
the review, which gains a third line since the title line is gone; the
logo sits at the picture's bottom right over a foot gradient, drop-
shadowed, the year under it — the streaming-app title card. A title
without a logo sets its name at 34px in the same corner over the same
gradient, so the title is always in one place. The band stays 224.

## Decisions

* **Corner, not seam.** The seam placement (on the dissolve at the
  picture's left edge) was rendered first and lands on the subject's face
  on most stills, because the crop rule centres the subject in the box.
  The bottom right is where a still has the least to lose, and the foot
  gradient makes it legible on a bright frame. The seam stays on the
  switchboard as the record of why not.
* **The fallback goes where the logo goes.** With the typed name on the
  left and the logo on the right, the mix moved the title around the band;
  now the corner is the title's place whatever its form.
* **Three review lines.** The text zone lost a line and the review takes
  it.

## Requirements

* *Backdrop and logo* — the most cinematic reading of it: the picture is
  the title card.
* *A good idea* — it is the title-card convention every streaming UI
  trained the reader on; the band does not grow.
* *Couch* — the logo at 72 over an .82 foot reads; the words are unchanged.

## Trade-offs

Gains: no growth, the most picture-led band, three review lines. Costs: the
title is read last — tile, words, picture, then the corner — which breaks
the sentence "Nick reviewed Charade" into two places; a corner logo on a
dark still against a dark foot is the least legible case of the round;
a band without artwork has no corner to put the title in and keeps the
typed line on the left. In the app: the logo `<img>` as a child of the band
positioned in the image box, a `.feed-band-foot` gradient, the title line
moved with it.
