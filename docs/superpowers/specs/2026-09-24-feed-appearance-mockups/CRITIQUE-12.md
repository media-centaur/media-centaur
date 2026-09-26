# Round 12 critique — where the picture sits and where the time sits

Rendered 2026-09-26 at 1920×1080 on Q6's page with R2's logo headline,
read at half size on `Q-place-switchboard/compare.html` with R2 beside
them.

## The complaint, located

Both halves of it have one cause: the still's box begins at 700, so the
text zone ends there and the time is right-aligned to a line in the
middle of the band. Every composition here moves the picture off the right
so the time can go to the edge; three of them also delete the crop.

## The four, scored

| | Picture | Reading order | Crop | Band | Verdict |
|---|---|---|---|---|---|
| **S1 Picture left** | 391×220 thumbnail, the whole frame | tile · picture · words · time | none | 264 | **Recommended** |
| **S2 Picture flush** | 469×264 at the band's edge | picture · tile · words · time | none | 264 | Bigger picture, the author mark displaced |
| **S3 Full bleed** | the band | tile · words · time at the corner | 38% slice | 264 | Keeps the reel; the only one that keeps a crop |
| **S4 Picture left, typed** | 320×180 | as S1 | none | 224 | S1 without the logo; the tightest band |

## Findings

* **The whole frame is a simplification, not just a look.** A 16:9 box at
  the band's height shows the still entire. The crop rule measured in
  round 4, the 38% offset for adjacent bands of one title, the mask and
  the scrim all go, along with `offset_crop?` and its adjacency logic in
  the projection. Two adjacent bands of one title now show the same frame,
  which is the truth.
* **The settled order survives in S1 and S4.** Tile, picture, words is
  the poster's anatomy with a wider picture. S2 puts the picture first and
  the tile second, which is the one thing every round since UIDR-038 kept.
* **The right half goes quiet.** With the picture on the left, a band
  without a review is words on the left and a time on the right with ink
  between. It is how every list reads; it is also less of a page than Q6.
  The 640px measure on the review keeps the words from chasing the time
  across the band.
* **The time at the edge needs ground.** On ink (S1, S2, S4) it needs
  nothing. On the picture (S3) it needs the right-edge vignette, which
  darkens the picture's clearest 300px to carry an 18px word.
* **S3 is the hedge.** If the dislike is of a box on the right, S3
  answers it while keeping the reel. If the dislike is of a large picture
  on the right, it does not.

## Added on the owner's ask: the logo on the picture

"What about S2 but the logo is atop the backdrop, like we do for the card
view on the home page?" Rendered as S5 (on S2's flush picture) and S6 (on
S1's inset thumbnail), both with `ContinueWatchingRow`'s treatment: the
to-top gradient, the logo bottom left, the white name as fallback.

| | Picture | Tile | Band | Verdict |
|---|---|---|---|---|
| **S5 Picture flush, logo on it** | 398×224, the band's left end | after the picture | 224 | **Recommended** — one artwork idiom with Home |
| **S6 Picture left, logo on it** | 320×180, framed | first | 224 | The same idiom with the settled order; a smaller card |

* **It is Home's card with a sentence beside it.** The Feed's band and
  the Continue Watching card become one thing: backdrop, gradient, logo
  bottom left, name in white when there is none. Home's rows and the
  Feed read alike, which round 4's brief asked for ("what it establishes
  is expected to propagate") and no direction until now delivered.
* **The panel empties to the sentence.** Who did what, the review, the
  seat. No title line, so the band stays 224 — the growth S1 and R2 paid
  for the headline logo is not needed.
* **The tile moves.** In S5 the author mark sits between the picture and
  the sentence, beside the name it marks, rather than at the band's edge.
  The reading is picture, author, sentence. S6 keeps the tile first at the
  price of a framed, smaller card. Rendered side by side, S5's order
  reads naturally: the picture names the title, the tile and the name say
  who, the words say what.
* **The frame's foot is dimmed**, as on Home, and the whole frame is
  shown, so the crop machinery stays deleted.
* **Fallback and mix.** A title without a logo sets its name in white on
  the picture, as Home does; a title without artwork keeps its typed
  title in the panel, since there is no picture to carry it.

## Recommendation

**S5** — the owner's composition. It answers both complaints (the picture
left, the time at the edge), keeps the band at 224, empties the panel to
the sentence, shows the frame whole, and makes the Feed's band and Home's
card one idiom. **S6** if the author mark must stay first. **S1** was the
recommendation before the ask and remains the best of the on-ink
compositions: the logo as the headline, the band 264.

Taken together with rounds 10 and 11, the Feed that answers every
complaint of the day is S5: Q6's dark page and flush columns with
hairlines; the poster gone; the still whole at the band's left with the
logo on it as Home draws it; the sentence beside; the time at the edge.

## In the app, for S5

`FeedBand`: the backdrop `<img>` at the band's origin at 16:9 (the 480 or
640 derivative at 398 CSS px), the card's gradient and logo block — the
`ContinueWatchingRow` markup, extracted into one shared component so Home
and the Feed draw it from one place — the tile and body offset by the
picture's width, the title line gone from the body, the time anchored to
`right: 20px`, the review at three lines. `FeedEntry` gains `logo_url`
from the ladder and loses `offset_crop?`; `FeedEntries` loses its
adjacency pass. The story pins a band with a logo, one with the white
name, and the no-artwork band.

## In the app, for S1

`FeedBand`: the backdrop `<img>` moves to the poster's position at 16:9
(the 240 derivative is too small; the 480 or 640 one at 391 CSS px), the
mask and scrim elements go, `--x-body` becomes the thumbnail's right plus
24, the time anchors to `right: 20px`, the body runs to the band's edge
with the review capped at 640px. `FeedEntry` loses `offset_crop?` and
`FeedEntries` its adjacency pass. The story pins a band with a logo, one
without, and the no-artwork band with its empty slot.
