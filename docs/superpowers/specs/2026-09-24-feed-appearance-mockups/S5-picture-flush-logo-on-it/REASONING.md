# S5 · Picture flush, logo on it — reasoning

**Knobs** picture `flush` · logo `picture` · time `edge` · on Q6's page. The owner's ask: "S2 but the logo is atop the backdrop, like we do for the card view on the home page".

## Style

The band's left end is a Continue Watching card: the still at full height
showing the whole frame (398×224), the Home card's to-top gradient (black
.85 at the foot, .2 at the midpoint, clear above), the logo bottom left at
16px, capped at 64 tall and 80% of the picture's width, drop-shadowed; the
typed name in white at 24px in its place when there is no logo; the year
under either. Beside it the tile, then a text panel that is only the
sentence — who did what, the review at up to three lines — and the seat;
the time at the band's right edge. The band stays 224.

## Decisions

* **Home's treatment, verbatim.** Gradient, corner, cap and fallback are
  `ContinueWatchingRow`'s, scaled to the band's picture. The Feed's band
  and Home's card become one artwork idiom rather than two.
* **The title leaves the panel.** With the logo on the picture the panel
  has no title line, so it does not grow: 224 holds a three-line review
  and the seat.
* **The tile between the picture and the words.** The author mark sits
  beside the name it marks; the picture, which names the title, comes
  first. The reading is picture, author, sentence.
* **The whole frame, dimmed at the foot.** The gradient darkens the
  picture's lower half, as it does on Home; the frame is whole, so the
  crop machinery stays deleted.

## Requirements

* *S2 with the logo atop the backdrop as Home does it* — exactly.
* *Not the image on the right, not the time in the middle* — as S2.
* *A good idea* — it is the app's existing card with a sentence beside
  it; a reader who knows Home knows the Feed.

## Trade-offs

Gains: one artwork idiom across Home and the Feed; the band at 224; the
sentence panel clean; the picture larger than S1's. Costs: the author mark
is second; the picture's foot is under the gradient; a bright frame at the
band's edge has no ink around it; a title without artwork has no picture
to carry its name, so its typed title stays in the panel. In the app: the
backdrop `<img>` at the band's origin at 16:9 with the card's gradient
and logo block (the `ContinueWatchingRow` markup, extracted), the tile
and body offset by the picture's width, the title line gone from the
body, the time anchored right.
