# G · The couch page — reasoning

Round 8: the Feed and Watchlist tabs as two full-height columns beside the Friends rail, at the couch floors, no masthead, no lead. Generated from data tables by a scratch script (not committed; the `.alt` crop derived from adjacency). No JavaScript. Three passes at 1920, each read at half size; once at 1280×800 and 2560×1440.

## Sizes — the spec

Content 1820 at 1920: the **feed column 1236**, a **24px gutter**, the **rail 560**. One strip across both — Feed · Watchlist · Friends at 22/500 with 18px counts, the scope pill (44 tall, 20px options) at the column's right edge — one hairline under all of it, 16px to the first unit. The rail has no heading: the Friends tab names it, and its first card says *How friends see you*.

| | Band | Rail card |
|---|---|---|
| Unit | 1236×224, radius 12, ink, 6 apart | 560 wide, radius 12, ink, 6 apart; padding 12/14 |
| Tile | 56 at x=20, centred; initial 22 | 48 at x=14, 3px down; initial 19 |
| Poster | 100×150 at (92, 24) | strip 72×108, radius 6, 8 apart, 8 under the line; an empty slot at a 6% fill |
| Text | x 210→700 | x 76→546 |
| Line 1 | 22/30 at 80%; name 500 at 96%; glyph 20 | name 22/28 600; the ago 18 at 66% right-aligned on its line |
| Line 2 | title 28/36 600; year 18 at 66% | presence 20/26 at 80%; title 500 at 96%; glyph 18 |
| Line 3 | review 22/30 at 78%, two lines | subtitle / note 18/24 at 66% |
| Time | 18 at 78%, right edge 700 | — |
| Seat | 32px at y 168–200; verbs 18, icons 20 | — |
| Picture | box `max(700, width − 900)` → 536×224, a **74% slice**; mask 240; scrim .93 at 700 · .55 at 820 · .16 at 940 · .04 at 1060 — the 360px dissolve | — |
| Cursor | 3px primary ring, scrim × .8, ground 13 → 16%, the seat shown | 3px ring, ground 13 → 16% |

Card heights: **shares watches 194**; **reviews only / listings only 104**; **You 128**; **nothing shared 78**. The rail of eight is 1184 with its foot.

Paging controls, all 32 tall and 20px at the tile's edge: **Show older** at 70%, a ghost 10px under the last band; the cap's foot line at 66% in the same seat; **"3 new"** at 84% on ink at .94 with a shadow and a 20px up-arrow, 12px from the viewport's top while scrolled. **All 30 friends** at 70% under the last card.

Lowest read text 66% on ink, about 10:1 — one secondary alpha. Crop `50% 30%`, `50% 38%` on the second adjacent unit of one title; twenty stills, no failure at 74%.

**The fold at 1080**: 937px under the strip — four bands (4 × 230) beside You, Cleo, Nick, Bob, Femi and Sam's head; the rail ends a quarter of the way down the first window.

## The four sharing states, as drawn

The presence line is the latest act of any kind, in the Friends card's words: *watched S01E03 of Pioneer One*, *reviewed Charade* ♥, *wants to watch Big Buck Bunny*. The strip's first poster is always the latest watch; every (a) person drawn has a watch as their latest act, so line and strip agree.

- **(a) shares watches** — Cleo, Bob, Femi: the line, then three posters. Femi's second slot is empty: Coffee Run has no artwork, the title the Feed's no-art band also shows.
- **(b) reviews only** — Ada, with the photo tile: the line, then *Doesn't share watching* at 18/66%.
- **(c) listings, not watches** — Nick (his line a review), Sam (a listing): as (b).
- **(d) nothing shared yet** — Theo: the line says so at 66%, no ago, nothing else.
- **You** first: the own tile, *How friends see you* under the name, the line, *You don't share watching*. Drawn as (c), not the brief's reviews-only: rows 6 and 16 are own listings in the Feed, and a reviews-only You would remove them. The note is the brief's words.

Order: You, then by latest act of any kind — Femi's watch (2d) lifts her above Sam's listing (3d), a move the Feed never shows. Eight cards; the other 22 are behind **All 30 friends**. A card and the link open the Friends tab; there is no *Manage friends* link because the tab is the management page and is in the strip at every width.

**Not the wall**: one card per person, replaced on the next act, bounded by the roster, never paged, never grown by activity; six episodes in a night are one line changing six times.

## Paging, as drawn

The window is twenty. The Feed tab counts the window, as the app does today (`length(feed)`): 20, 40, 60; a smaller scope counts what it has (You 5). **Show older** appends twenty; after the third, sixty bands sit in the DOM and the foot reads **"That's the last sixty."** — not "the last two months": the window is a count, and a count is true at any roster's pace, where a span is true only at one. Arrivals: at the page's top they prepend live (the column moves down one band); scrolled, they queue behind **"3 new"** at the column's head, which prepends and scrolls to the top when pressed. The number is the queue in the current scope. Neither the scope nor Show older touches the rail; at the column's foot the rail's cell is empty, since the rail ended a window above.

## The fold

A container query at 1600 (a 1700 viewport). Below it the rail is not drawn, the strip's grid collapses to one column, the three tabs stay, and the column keeps every size: at 1180 the box is 480 (an 83% slice). At 2560 raw the cap bites — the box is 900 from x=976 with ink between the time and the picture, a 43% slice — but the app composes 2560 at 1920 CSS px, so this is a safety, not a state.

## The 10-foot check

Half of the 1920 render: every sentence, title, review, time, name, presence line and initial reads; the 18px years, agos and notes at 66% are the floor and read. It changed one thing: the rail's strip. At 64×96 a poster halved to a 32×48 swatch; at **72×108** (36×54 halved) the bunny and the *One Step Beyond* face still read. The cost is 12px per watch-sharing card. "3 new" and "Show older" read at half size on their ink.

## Rules touched

| Rule | Status | The exception, precisely |
|---|---|---|
| UIDR-038 rule 7 — You first, name as title, key in the footer | Bent | The key and the added date live on the Friends tab |
| Rule 8 — presence at the header's right | Bent | Under the name; only the ago on the right |
| Rule 9 — the poster strip, "all N", text rows | Bent | Three posters; no "all N", no rows — the tab has them |
| Rule 10 — the You card's border, subtitle, no footer | Bent | The own tile replaces the border; the subtitle stays |
| *Wall of watching* | Bent, rail only | Watching as presence and three posters, per person, replaced; the Feed still excludes it |
| *Social-network chrome*, *state as decoration* | Kept | No counts, handles, reactions; the note is a fact, not a colour |
| UIDR-045 rules 3 and 5, the toolbar contract | As R1 | The own tile; units 6 apart; the seat unchanged; the pill scopes the Feed only |
| UIDR-033 | Bent in the rail | A person's card carries the posters of what they watched — the card's stated fact |
| DESIGNER.md group headers | Kept | The rail has no heading |
| The brief's 64×96 strip | Bent | 72×108 after the half-size check |
| Crop rule, text ≥ 55%, 120ms ceiling, hover height, no JS | Kept | |

## If the owner prefers 1b

The first band becomes R1's lead: 1236×380, tile 64, poster 200×300, headline 44, the box from 700 at the whole height. The fold holds the lead and two bands beside the same five cards; an arrival becomes the lead and the old lead demotes to a band (poster 200 → 100, title 44 → 28), so "3 new" prepends a lead; the Watchlist keeps no lead, since a list has no newest. Nothing in the rail changes.

## The one thing I am least sure of

The strip has no label. It reads because every drawn watch-sharer's latest act is a watch, so the line names the first poster. When such a person's latest act is a review, three posters under *reviewed Charade* could read as reviewed titles. The fix is a *Recently watched* caption at 18/66% above the strip, 24px per card — one more line on which the rail's card and the tab's card would have to agree.
