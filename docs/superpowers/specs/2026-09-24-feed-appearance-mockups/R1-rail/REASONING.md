# R1 · The rail — reasoning

Round 7: the cinematic feed re-scaled for a couch, beside a Friends rail. Generated from data tables by a scratch script (not committed) so the crop offset is derived from adjacency, never typed. Rendered four times at 1920 with a half-size copy read each time, once at 1280×800 and 2560×1440. No JavaScript.

## The page

Content 1820 at 1920: a **feed column of 1236**, a **24px gutter**, a **rail of 560**. One strip runs across both — Feed · Watchlist and the scope pill over the column, the rail's heading "Friends" over the rail, one hairline under all of it. Nothing frames either column.

One constant, **700**: the text zone's right edge, where a band's words end, its time sits and both picture boxes begin. Both boxes are 536 wide — one picture edge down the column.

## Sizes at the couch floors

| | Band | Lead | Rail row |
|---|---|---|---|
| Unit | 1236×224, radius 12 | 1236×380, radius 16 | 560×108, no surface |
| Tile | 56 at x=20, centred on the band; initial 22 | 64 at x=32, centred on line 1; initial 26 | 48 at x=12; initial 19 |
| Poster | 100×150 at (92, 24) | 200×300 at (120, 40) | 60×90 at x=74 |
| Text block | x 210→700 (≈43ch) | x 344→800 | x 148→548 |
| Line 1 | 22/30 at 80%; name 500 at 96%; glyph 20 | 26/34; glyph 24 | name 22/28 600 on a fixed line |
| Line 2 | 28/36 600; year 18 at 60% | 44/52, wraps to two lines, the year 20 after its last word | presence 20/26 at 80%, the title 500, one line |
| Line 3 | 22/30 at 78%, two lines | 22/32 at 78%, three lines | You: subtitle 18 at 60% |
| Time | 18 at 78%, right edge 700, on line 1 | 20, top right | 18 at 60%, right-aligned on the name's line |
| Seat | 32px at y 168–200; verbs 18, icons 20 | 32px at y 308–340 | — |
| Picture | 536×224 from x=700: a **74% slice** | 536×380: the whole height, 79% of the width | — |
| Dissolve / scrim | 200px mask; .97 · .93 at 700 · .55 at 800 · .16 at 900 · .04 at 1000 · 0 | the same, plus .32 → 0 to the left over 240 under the time | — |
| Cursor | 3px primary ring; the scrim × .8, the ground 13 → 16%, the seat shown | same | 3px ring and a 6% fill |

Chrome: h1 30; tabs 22 with 18px counts; the pill's options 20; the rail's heading 22 at 60%. Watchlist band: no tile, the poster at x=20, the title 28 first with "Movie · 2010" at 18, notes 22/30 to three lines, the row markers in the seat at 18/66% always on, pennants 30 tall at 18/600 on the right edge over a .48 vignette only this band has. You-empty 26/34 and 22/32; Show older and Manage friends 18px, 32 tall.

Lowest read text 60% (year, ago, the rail's subtitle and heading); markers 66%. Every read word sits on ink under a ≥ .93 scrim or on the page ground (about 7:1 at 60%), except the lead's time (20px, the .32 layer, a shadow) and the last 100px of a lead review line, over an image at most half opaque under a scrim of at least .55.

Crop: `50% 30%` everywhere; `.alt` → `50% 38%` on the second adjacent unit of one title. At 74% every still lands its subject whole, the Cosmos Laundromat sheep's crown included.

## The rail

**Anatomy.** The band's spine at rail scale: tile, poster, words. Per person: the tile (monogram, photo, or the filled own tile); the name with the ago in its own seat at the row's right edge; the **presence line in `ActivityWords`' vocabulary** — "watched S01E03 of Pioneer One", "reviewed Charade", "wants to watch Big Buck Bunny". The poster is the title the person **last watched**: the line's own title on a watched line, a second fact on the others (Nick reviewed Charade; his poster is Caligari). Nothing shared: the slot empty at a 6% fill, the line at 60%, no ago. You: first, the own tile, "How friends see you" as the subtitle. At the foot, **Manage friends** as a link; keys, Add and Remove live there, not drawn. Order: You, then friends by latest activity of any kind, then nothing shared — `People.sort_key/1`.

**At thirty.** The rail scrolls with the page — one scroll region, which a gamepad wants. Thirty rows are 3,284px, a window of sixteen 3,830px: the rail runs about the first window's length; the feed continues alone under it and Show older pages only the feed.

**Why it is not the wall.** UIDR-038 excludes watched from the Feed because a run of episodes is a wall of one title. The rail holds one line per **person**, replaced on the next act, never appended; ordered by people, capped at the roster, no history behind it; six episodes in a night are one line changing six times. Presence beside a Feed that stays what people said.

## What folds at 1280

A container query at 1500px. Below it the rail is not drawn, its heading leaves the strip and the **Friends 30** tab returns; the column takes the 1180, the band's box 480 wide (an 83% slice), every size and seat unchanged. The Friends tab shows the rail's rows in **two rail-width columns**, row-major by activity, Manage friends under them. At 2560 raw the box is 1176×224, a 34% slice, safe by the measurement; the UI scale renders 2560 at 1920 CSS px anyway.

## The 10-foot check

At half size every sentence, title, review, name, presence line, tile letter and time read; the 18px items are the floor. It changed two things. The **lead's time**, the one read text on the picture, was the weakest read: 18 → 20, the lead's own secondary size. The rail's **names lost their pitch**: text blocks centred on the poster put You's three-line block 12px above the others' names, so the name now sits on a fixed line in every row.

## What a new arrival does

The new action becomes the lead; the old lead becomes band 1 — its still re-crops to a 74% slice, its poster 200 → 100, its title 44 → 28 — and everything below moves down 230px. The rail moves on its own clock: a friend's act moves their row up and rewrites it; no row is added or removed until a friend is.

## The alternative tried

B's full-bleed lead in the column (the still 1236 wide, a 55% slice), from a scratch copy. Dramatic — Sintel's face fills the lead — and wrong for the rule: the crop cuts her crown, the subject sits under the words' edge, a centred subject would be under the poster. The boxed lead shows the whole frame height with the subject clear. The critique's decision holds.

## Rules touched

| Rule | Status | The exception, precisely |
|---|---|---|
| UIDR-038 rules 7–10 — the Friends card | Bent | Rule 7: You first and the name as title kept; the key and added date move behind Manage friends. Rule 8: the presence line under the name, only the ago on the right. Rule 9: one poster, the latest watched; the shelves open with the person. Rule 10: the own tile replaces the border, the subtitle stays, no row has a footer |
| UIDR-038 *wall of watching* | Bent, rail only | Watched as presence: one line per person, replaced, capped at the roster; the Feed still excludes it |
| UIDR-038 *social-network chrome* | Kept | No counts, handles or reactions in the rail |
| UIDR-045 rules 3 and 5, the toolbar contract | As F | The own tile; units 6px apart; the seat unchanged |
| UIDR-045 — the scope pill | Kept | It scopes the Feed only; the rail ignores the scope |
| UIDR-033 — artwork when it is the subject | Bent in the rail | The poster is the artwork of the row's stated fact, on a person's row — P's bend at 60×90 |
| Page shape | New | A main column with a rail; no other page has it |

## The one thing I am least sure of

Whether the lead is enough of a lead at 1236. Its picture box is the bands' width; it is taller, its type and poster larger, it shows the whole frame where a band shows three quarters — but it reaches no further right than a band, as F's did. If the owner wants the lead wider as well as taller, R3's masthead is the answer, not a change to this column.
