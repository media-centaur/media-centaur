# R3 · Masthead — reasoning

Round 7: F's cinematic feed at the couch floors, the lead spanning both columns, a Friends rail beside the bands. One `index.html`, generated from the data table by a scratch script (the `.alt` crop offset derived from adjacency, never typed); no JavaScript. Rendered three times at 1920, once at 1280×800 and 2560×1440, once at half size, once for the alternative.

## What the user sees at 1920

Under the strip (Feed · Watchlist — the Friends tab *is* the rail), the newest action is a **lead** 1820 wide; under it the **feed column** (1236px) of bands beside the **rail** (560px, 24px gutter) headed *Friends*. One material below the strip: ink units (`oklch(13% 0.02 264)`, 6px apart, no border, glass or hairline) in three sizes. The cursor ring is 3px primary on every unit; hover multiplies the scrim alphas by .8 and lifts the ground 13% → 16%; only the seat fades (120ms).

### Sizes, at or above the floors

| | Lead | Band | Rail entry |
|---|---|---|---|
| Unit | 1820×388, radius 16 | 1236×220, radius 12 | 560×132, radius 12 |
| Tile | 64 at x=36, on line 1; initial 26 | 56 at x=20, centred; initial 22 | 48 at x=16; initial 19 |
| Poster | 200×300 at (124, 44) | 112×168 at (96, 26) | 72×108, right-aligned |
| Text zone | 352→900 (≈50ch at 22px) | 232→680 (≈41ch) | 80→456 |
| Sentence | 26/34 at 80%; name 500/96%; glyph 22 | 22/30; glyph 18 | name 22/28 600; presence 20/26 at 80% |
| Title | 44/50, two-line clamp; year 22 at 66% | 28/34; year 18 at 66% | — |
| Review | 22/30 at 78%, three lines | 22/28 at 78%, two lines | subtitle 18/24 at 66% (You) |
| Time | 18 at 78%, top right over a .30 vignette | 18 at 78%, right edge at 680 | 20 at 66% after a middot |
| Seat | 32px at y 312–344; verbs 18, icons 20 | 32px at y 162–194, the poster's foot | — |
| Picture box | from 900: 920×388, **75% slice**; dissolve 300; ≈620 clear | from 680: 556×220, **70% slice**; dissolve 200; ≈356 clear; cap 900 | — |

Chrome: h1 28; tabs 22, counts 18; pill 44 tall, 18px options; ghosts 18 at 66%. Lowest read text 66% on ink, ≈10:1; the weakest is the lead's time over the vignette, carried by the shadow as in F. Crop: `50% 30%`, `50% 38%` on the second adjacent unit of one title; sixteen stills, no failures at a 70% slice.

**The lead's box begins where its words end (900), not at the band's 680.** F ran the lead's words over the dissolve at 16px; at 22px the review needs ink under it. The alternative, rendered, puts You · Charade's review across Grant's face under a .55 scrim — legible, wrong. Chosen: Grant whole in the dissolve, Hepburn clear; cost 220px of picture. One formula serves both sizes: `box = clamp(min, width − text zone, cap)` — band 680/cap 900, lead 900/floor 460.

**The fold at 1080**: the lead, two bands and a third's top beside four people — the masthead costs a band per screen and buys the still at 1820.

## The rail

Presence: one line per person, ink units, You first, then by the line's time. Per entry: tile · name · presence line with the time · one poster. *Manage friends* at the foot is a link to today's Friends tab content. Nothing else — no strip, no "all N", no counts, no key, no Remove; those open with the person.

**The line is the person's latest watch, falling back to the card's presence.** The owner's pitch was "what they've been watching, ordered by latest watching activity", and the critique's case for the rail was the one fact the Feed excludes. Cleo's lead says *wants to watch Sintel*; her rail line says *watched S01E03 of Pioneer One · 45m ago* (the app's words, `ActivityWords.presence/4`). Sam and Ada have shared no watch, so their lines fall back to the card's presence and repeat a Feed band — the fallback's honest cost. **The poster is always the line's title**, so an entry is one fact, not two. Femi's Coffee Run has no artwork: the slot, empty. Theo: *Nothing shared yet*, no poster.

**Not the wall.** The rail is bounded by the roster, not by time: a person appears once, nothing pages, it never grows with activity, and a title appears because a person is, not because it was watched.

**The same person twice** (state 3): the lead says *You reviewed Charade*; the rail's You entry says *watched The Cabinet of Dr. Caligari · 3h ago* with that poster and the subtitle *How friends see you*. Different fact, different picture, by construction — the lead is your shared action, the rail your watching. Only with no shared watch does the fallback echo the lead, and then the subtitle names it: the audit view, whose function is the mirror. The filled tile on both is the mark, like the name.

The rail ignores the scope pill (states 2, 4). **At thirty**: ≈4,200px against the feed's first window of 3,800; the rail is in the page's flow — one scroll, one cursor space, nothing nested for a gamepad — ordered so the people watching now are in the fold.

## The Watchlist with the rail — no lead

A lead promotes the newest; a list has no newest, and 388px on its first title would say "this matters most", which is false. State 12: eight 220px bands, P's anatomy re-scaled (poster at the edge, title first, markers in the seat, 30px pennants at the right edge), beside the same rail.

## 1280 and 2560

Under 1700px the page folds (a container query on `.page`; state 13's 1180px wrapper and the real 1280 viewport share the rule): the rail disappears, the strip reads **Feed · Watchlist · Friends 30**, the lead takes the column with its box at the 460 floor (the still's centre 67%), the band's box is 500 (78%), and a long title wraps to two lines with the year after its last word (state 9). Sizes unchanged. At 2560 the lead's box is 1560×388 (44%), the band's caps at 900 (43%) with 296px of ink before it; the rail stays 560.

## The 10-foot check

Half of the 1920 render: every sentence, title, review, time and initial reads; posters read as pictures. Faintest: the years, the rail's times and *How friends see you* at 60%, and the 64×96 rail poster halved to a swatch. Changed: the /60 secondaries to /66 (the seat's plain-state value — one secondary alpha) and the rail poster to 72×108, the entry to 132. Nothing was resized down.

## A new arrival

The new action becomes the lead; the old lead becomes band 1 (box 920×388 → 556×220, poster 200 → 112, title 44 → 28) and every band moves 226px; the lead's height is fixed, so the top holds. The rail re-sorts only when a person's line changes; the feed does not move for that.

## Rules touched

| Rule | Status | Exception |
|---|---|---|
| UIDR-038 rule 7 — You first, name as title, key in the footer | Bent | Key and footer live behind Manage friends |
| Rule 8 — presence at the header's right | Bent | Under the name; the poster at the right |
| Rule 9 — poster strip, "all N", text rows | Broken in the rail | One poster of the line's title |
| Rule 10 — the You card's border, subtitle, no footer | Bent | The tile replaces the border; the subtitle stays |
| *Wall of watching*; *social-network chrome*; *title-first* | Kept; bent as F | The rail is bounded by the roster; the tile; the title largest on the lead only |
| UIDR-033 | Bent in the rail | The poster is the stated fact's title, beside the fact |
| UIDR-045 rules 3, 5, toolbar | As F | Plus two columns at ≥ 1700 |
| The rail brief | Bent | The line prefers the latest watch; the poster is the line's title |
| DESIGNER.md group headers | Bent | *Friends* is the rail's name, replacing the tab |
| Crop rule, text ≥ 55%, 120ms ceiling, hover height, no JS | Kept | |

## The one thing I am least sure of

The rail's line rule. Preferring the latest watch gives the rail its own content and answers the You-twice case structurally, but "presence" then means one thing on the Friends card and another in the rail. The alternative — the card's rule plus a separate latest-watched poster — is one definition and two facts per line. If the owner wants one definition, the card should adopt the rail's, not the reverse.
