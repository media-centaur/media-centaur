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

## Added on the owner's notes: T5

The owner liked T4 most and gave two notes: the act glyphs over the rail's
posters should be centred, and the tile should sit at the top of the row
as it does on the person card. Both rendered as knobs and as **T5**.

* **Centred glyphs are right for the posters the rail actually shows.**
  Most acts are one act. In the fixed slots a lone bookmark sits at the
  poster's right edge and a lone opinion at its left, and the eye reads
  both as misplaced. Centred, one act sits in the middle, two as a pair,
  and three land exactly where the slots put them. What is given up is
  UIDR-046's scan — "the eye" at one x on every poster — which the owner
  has judged less valuable than balance. The order within a group is
  kept.
* **The tile at the top is how a text row reads.** The band centred its
  tile beside a 224px picture; on a row of words the centred tile floats
  between lines. Hung from the top line it pairs with the name on line 1
  and matches the person card. The poster hangs from the same line so
  the row's three columns share one edge.
* **Nothing else moved**, so T5 is T4 as the owner saw it, corrected.

## Recommendation

**T5** — T4 with the two notes. The rows on the page at 1500, hairlines
between, the tile and poster hung from the top, the rail's glyphs centred.
It is the page the owner chose, made right by their own notes.

Before the notes the recommendation was **T1**, the list surface — the
inset container gave the two columns edges T4 does without. That remains
the one thing to look at on T5: the feed and the rail are told apart by
their content and the gutter alone. If that reads fine on the TV, T5
stands; if not, the `surface` knob turns T5 into T1 with the notes kept.

The earlier recommendation stands as the record:

**T1** — the poster row on the list surface at 1500. It is the app's own
idiom at the couch floors, it answers every complaint of the day by
removing the cause rather than treating it, and it deletes the crop
machinery. **T2** if Discovery should rejoin the 1280 container like every
other page and the shorter measure is acceptable. T3 and T4 are honest
but each drops something T1 keeps: T3 the app's ground, T4 the columns'
edges.

## In the app, for T5

`FeedBand`: the backdrop `<img>`, the scrim and the image box go; the time
anchors to the row's right; the body runs to the edge; the tile and the
poster take `top: var(--pad-y)`. `.feed-column` and `.discovery-rail` lose
their unit grounds and take hairlines between children; no container.
`PersonCard`'s act slots become a centred flex row and `--x1/--x2/--x3`
are deleted. Discovery's content caps at 1500. `FeedEntry` loses
`offset_crop?` and `backdrop_url`; `FeedEntries` loses the adjacency pass.
The story pins a row with a review, one without, and the no-artwork row;
the person card's story pins one, two and three acts on a poster.
UIDR-046 records the row, the width, the centred glyphs (amending the
fixed slots) and that the Feed carries no still.

## In the app, for T1

As T5, except `.feed-column` and `.discovery-rail` take `glass-inset`
with a 12px radius as the container. Discovery's
content caps at 1500. `FeedEntry` loses `offset_crop?` and `backdrop_url`;
`FeedEntries` loses the adjacency pass; the projection stops reading
backdrops for the Feed. The story pins a row with a review, one without,
and the no-artwork row. UIDR-046 records the list surface and the width,
and that the Feed carries no still.
