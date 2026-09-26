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

## Recommendation

**S1** — the still in the poster's slot as a whole-frame thumbnail, the
time at the edge, the logo as the headline. It answers both complaints by
the same move, keeps the reading order every round has kept, and deletes
the crop machinery rather than tuning it. **S4** is the same answer if
round 11 lands on no logo. S2 if the picture should be bigger and the
author mark can come second. S3 if the reel must stay.

Taken together with rounds 10 and 11, the Feed that answers every
complaint so far is: Q6's dark page and flush columns with hairlines; the
poster gone and the logo as the headline; the still whole at the left; the
time at the edge. That page is S1.

## In the app, for S1

`FeedBand`: the backdrop `<img>` moves to the poster's position at 16:9
(the 240 derivative is too small; the 480 or 640 one at 391 CSS px), the
mask and scrim elements go, `--x-body` becomes the thumbnail's right plus
24, the time anchors to `right: 20px`, the body runs to the band's edge
with the review capped at 640px. `FeedEntry` loses `offset_crop?` and
`FeedEntries` its adjacency pass. The story pins a band with a logo, one
without, and the no-artwork band with its empty slot.
