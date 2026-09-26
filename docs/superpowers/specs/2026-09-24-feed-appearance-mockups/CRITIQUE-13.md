# Round 13 critique — no backdrop: the poster row in narrower columns

Rendered 2026-09-26 at 1920×1080 and read at half size on
`Q-row-switchboard/compare.html` with S5 beside them.

## What the still was doing, seen without it

Every complaint of the day traced to the still: the dark box it sat in, the
second picture beside the poster, the time pinned to its edge, the picture
on the right. Without it the row is the anatomy UIDR-038 named — tile,
poster, three lines, the time, the seat — and the page is a list. The
campaign's "holy crap" bar of round 4 is set aside by this choice; what is
kept is everything else it settled: the couch floors, the two columns, the
person card, the identity tile.

## The four, scored

| | Surface | Width | Like the app | Verdict |
|---|---|---|---|---|
| **T1 List surface, 1500** | inset container, hairlines | 916 + 560 | Watch History's idiom | **Recommended** |
| **T2 List surface, 1280** | the same | 776 + 480 | the app's container and alignment | The alternative if consistency outranks measure |
| **T3 Dark sheet, 1500** | Q6 without the still | 916 + 560 | Discovery's own dark page | A dark list; the ground has less to justify it |
| **T4 Open rows, 1500** | none | 916 + 560 | the ground and type; no container | The two columns lose their edges |

## Findings

* **The row settles at 206.** Twenty-pixel pads, line 1 at 30, the title
  at 36, two review lines at 60 and the 32px seat. The poster's size does
  not move it; the words do. It cannot come lower at the couch floors
  without dropping a review line or moving the seat, and both were
  settled.
* **1500 is the width the row wants.** At 1820 a row without a review is
  words at the left and a time at the right with ink between; at 1280 the
  feed is 776 and a review of ordinary length wraps to three lines and
  clips. 916 holds two lines at a reading measure.
* **The list surface answers the boxes without a dark ground.** The inset
  container sits within a few percent of the app's ground, so it reads as
  a surface, not a hole, and the hairlines carry the rhythm. Round 10's
  darkening was needed because the units were ink; here they are not.
* **The rail fits 480.** The person card's three posters and their gaps
  need 408; nothing in the card changes for T2.
* **The poster's printed title still doubles the typed one.** Round 11's
  diagnosis stands; the logo headline is on the switchboard for a title
  beside a poster, and it doubles the title in two graphic forms, which is
  why it is not a preset here.
* **What is lost.** The still was the campaign's presence. T1 is calm and
  correct and looks like the app; it does not look like round 4 asked
  for. That is the owner's call, made with the page in front of them.

## Recommendation

**T1** — the poster row on the list surface at 1500. It is the app's own
idiom at the couch floors, it answers every complaint of the day by
removing the cause rather than treating it, and it deletes the crop
machinery. **T2** if Discovery should rejoin the 1280 container like every
other page and the shorter measure is acceptable. T3 and T4 are honest
but each drops something T1 keeps: T3 the app's ground, T4 the columns'
edges.

## In the app, for T1

`FeedBand`: the backdrop `<img>`, the scrim and the image box go; the time
anchors to the row's right; the body runs to the edge. `.feed-column` and
`.discovery-rail` take `glass-inset` with a 12px radius and hairlines
between children; the bands and cards lose their own ground. Discovery's
content caps at 1500. `FeedEntry` loses `offset_crop?` and `backdrop_url`;
`FeedEntries` loses the adjacency pass; the projection stops reading
backdrops for the Feed. The story pins a row with a review, one without,
and the no-artwork row. UIDR-046 records the list surface and the width,
and that the Feed carries no still.
