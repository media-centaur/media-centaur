# R2 · Logo headline — reasoning

**Knobs** logo `headline` · logo height 72 · mix `some` · still `wide` · on Q6's page.

## Style

The title in its own lettering where the typed title was. Line 1 says who
did what; the logo, in a 72px box left-aligned at the tile's right, says
which title, with the year at its foot; the review follows. The band grows
by the logo's height (192 + 72 = 264) so a two-line review and the seat
still fit under it. A title without a logo sets its name at 34px, bottom-
aligned in the same slot, so the column's rhythm holds across the mix.

## Decisions

* **The logo is line 2, not a picture.** It replaces the typed title
  exactly — same slot, same reading order (who, what, said what) — so the
  band's sentence is unchanged; only the title's typography is the film's.
* **On the ink, not on the picture.** Readability is the settled priority;
  a logo on ink at .93 reads at any size and any colour, and the still's
  subject is never covered.
* **The band grows.** 264 fits a 72px logo over a two-line review and the
  seat. The fold at 1080 shows three and a half bands instead of four. The
  56px box on the switchboard gives 248; the 96 gives 288.
* **The fallback at 34, not 28.** Beside a 50px wordmark a 28px typed title
  looked like a caption; at 34 it holds the slot.

## Requirements

* *Backdrop and logo* — exactly that; the poster's identity role is taken
  by the title's own mark.
* *A good idea* — the app's hero and marquee already do logo-else-name in
  this position; the Feed joins them.
* *Couch* — the words are unchanged; the logo reads at 72 from the couch.

## Trade-offs

Gains: each band identified by its title's typography; no second picture;
the sentence order kept. Costs: 40px per band; a column of real logos will
be louder than these stand-ins, in colour and style, and the mix with typed
fallbacks is visible (deliberately so). In the app: `FeedEntry.logo_url`
from the ladder the projection already calls, the logo `<img>` in the
band's body between line 1 and the review with the typed title as its
fallback, `--h` by mode.
