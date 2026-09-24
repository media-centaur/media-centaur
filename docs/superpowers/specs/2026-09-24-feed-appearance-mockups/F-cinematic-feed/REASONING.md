# F · The cinematic feed — reasoning

Round 6: the one assembled page — C's band, A2's lead, the critique's settled table; nothing re-opened but the lead's image box. No JavaScript; generated from the data table by a scratch script (not committed) so the crop offset is derived from adjacency, never typed. Rendered three times at 1920 (the fold twice, the whole column at 1920×3000), once each at 1280×800 and 2560×1440, every state clipped.

## What the user sees

One unit at two sizes, 6px apart on the page ground, full width (`.content{max-width:none}`: 1820px at 1920). No border, glass, shadow or hairline. Left to right on both: identity tile, poster, text block (sentence · title and year · review), the seat at the poster's foot, the time, the picture. Ground `oklch(13% 0.02 264)`.

Two constants: **576**, the text zone's right edge, left of which no image box begins; **360**, the px over which every box's left edge dissolves (a mask, transparent → opaque). The box's left edge is `max(576, width − cap)`.

| | Band | Lead |
|---|---|---|
| Unit | 1820×152, radius 10 | 1820×340, radius 14 |
| Image box | cap 900: from x=920 at 1920 (900 wide), 576 at 1280 (604), 1560 at 2560 | no cap: from x=576 — 1244 wide at 1920, 604 at 1280, 1884 at 2560 |
| Slice of the still | **30%** at 1920 (45% at 1280) | **49%** at 1920 (whole at 1280; 32% at 2560) |
| Clear picture past the dissolve | ≈540px | ≈884px |
| Ink between words and box | 344px at 1920; 0 at 1280; 984 at 2560 | none — the words end at 800, on the dissolve |
| Tile | 40px at x=18, centred on the band (top 56); initial 16/600 | 48px at x=32, centred on line 1 (top 50, the poster's top); initial 19/600 |
| Poster | 72×108 at (74, 22); radius 6; shadow `0 3px 12px` black/55 | 160×240 at (100, 50); radius 8; shadow `0 10px 28px` black/55 |
| Text block | x 164→576 (≈53ch at 14px), top 22, height 108 | x 280→800 (≈58ch at 16px), top 50 + 11 padding, height 240 |
| Line 1 | 15/22 at 80%; name 500 at 96%; glyph 13px; 64px right padding | 18/26; glyph 16px |
| Line 2 | 18/24 600 at 100%; year 13px at 60%, 9px gap; 1px above | 32/38; year 15px; 2px above; `drop-shadow(0 2px 10px black/85)` |
| Line 3 | 14/20 at 78%, two lines, 5px above | 16/24 at 78%, three lines, 10px above |
| Time | 13/22 tabular at 78%, right edge at 576 (the body's edge = the picture's start), top 22 | 13/26 at 78%, right edge 32 from the unit's edge (the body's edge = the padding), top 61 (line 1) |
| Seat | 20px at y 110–130, from x=158 | 20px at y 270–290, from x=274 |
| Scrim, to the right (× `--s`) | base hue: .97 at 0 · .93 at bx · .55 at bx+180 · .16 at bx+360 · .04 at bx+540 · 0 at the edge | the same recipe and anchors |
| Scrim, to the left (× `--s`) | — | .30 at the edge → 0 at 220px, holding the time |
| Text shadow | `0 1px 3px` black/85 on the block, black/90 on the time | same |
| No artwork | ground `--glass-inset-bg`; scrim .35 → 0 over 800px; `.poster-empty` with a 1px white/6 edge; same height | same at 340 |

**Crop.** `object-fit: cover; object-position: 50% 30%` on every backdrop; the second of two adjacent units of one title carries `.alt` → `50% 38%`, derived from adjacency in the scoped window; no per-title position exists.

**Hover.** `--s: .8` multiplies every scrim alpha; the ground lifts 13% → 16% (no-artwork: `oklch(20% 0.017 264/.5)`); both instant. The seat's 120ms opacity fade is the only transition. Heights constant.

**Identity tile.** Monogram: primary at 18% fill, a 1px inset ring at 22%, shadow `0 2px 8px` black/35, the initial in `--p` at 600. Own: `oklch(62% 0.16 264)` fill, the initial `oklch(96% 0.008 264)` at 700. Photo: a circular crop, a 1px inset ring white/18. Own with a photo: a 2px ring of the same fill. "You" is set like any name, 500 at 96%.

**Toolbar.** 13px at 78%; verbs 20px tall, 6px padding, radius 6, 10% fill on hover; icons 14px. Friend: List · Download · Ignore (Ignore last, 10px gap). Own: List · Download. Listed filled at 96%. Tracking, In library, Downloading as plain words at 66%; Downloading's 3px hairline at `--pct`. No Delete.

**Cursor.** A 2px primary ring as the unit's top layer (`::after`, inset 0, radius inherited).

**Chrome.** Tab strip 14px, the `.seg` pill on its line at the right, one hairline under both. Feed 16 · 11 · 5 by scope; Friends 30; omitted at zero. Show older: a ghost button 10px under the last band. You-empty: headline 17/600, body 14 at 70%, one ghost action, no lead.

Lowest read text: the year at 60%; plain states 66%; everything else ≥ 78%.

## The lead's image box — decided by the render

**Uncapped** (A2's: from the text zone's edge, 1244×340 at 1920, a 49% slice) is in states 1 and 3; **capped at 900** like the band's (900×340, a 67% slice) is state 14.

Capped, Sintel: the dragon's head falls into the dissolve, Sintel's face stands alone, and the lead's left 920px is ink holding two lines. Capped, You · Charade: Grant's face under the dissolve, Hepburn alone, and between the review's last word and the clear picture lie 120px of ink and 360px of dissolve — C's band gutter at 340px tall. Uncapped, Sintel: the dragon under .55 → .10 in the dissolve, Sintel clear. Uncapped, You · Charade: Grant a ghost at x≈800, Hepburn clear at 1370 — the two-shot. Ada · Night of the Living Dead (state 10), uncapped: the moon in the dissolve, both figures clear.

**Uncapped.** The cap exists to hold the band's slice at the measured 30%; at 340px the uncapped box already gives 49%, inside the range the lead measured forgiving. The cap buys nothing measured and costs the second subject on every still rendered plus a 480px gap at the lead's height. One rule survives: `max(576, width − cap)` on both sizes, the band's cap 900, the lead's its full width. The lead's picture begins 344px left of the bands' — larger in every dimension, which is what a lead is.

## 1280 and 2560

**1280×800.** Units 1180 wide. The lead's box is 604×340, and so is a 16:9 still: the whole frame shows, 244px clear — a card beside a headline, not A2's sliver. The band's box is 604 from 576, no ink, a 45% slice.

**2560×1440.** Units 2460 wide. The lead's box is 1884 wide, a 32% slice: Sintel from brow to chin — A's full-bleed lead at 1920. The band's box stays 900 and the ink is 984px, C's known limit; the app's UI scale renders 2560 near 1920 CSS px, so this is the forced-scale edge.

## What a new arrival does

The new action becomes the lead; the old lead becomes band 1 — its still re-crops from 49% in a 1244px box to 30% in a 900px box whose left edge moves 576 → 920, its poster to 72×108, its title to 18px — and everything below moves down 158px. The lead's height is fixed, so the top of the page holds. `.alt` re-evaluates on render (an arrival of the lead's own title puts it on the old lead). A scope change re-projects from the newest action in scope; an empty You has no lead.

## Standing rules: kept, bent, broken (A2's and C's ledgers, merged)

| Rule | Status | Exception, precisely |
|---|---|---|
| UIDR-038 rules 2 and 3; *hover jump*, *grouped rows*, *state as decoration*, *day dividers*; UIDR-033; the toolbar contract; colour is signal; text ≥ 55%; the 120ms ceiling; the crop rule | Kept | Size is index 0 vs the rest; `.own` changes the tile's fill only; heights constant; year 60% the floor |
| UIDR-038 *wall of watching* | Bent | Half picture; every unit leads with a sentence about a person in a fixed text zone, the picture after the words |
| UIDR-038 *title-first row* | Bent, lead only | The title is the lead's largest type (32px) under an 18px sentence; reading order stays tile, sentence, title |
| UIDR-038 *social-network chrome* | Bent | The tile is the Friends tab's monogram; the photo slot is the owner's note; no handles, counts, reactions |
| UIDR-045 rule 3 — own = "You" in the primary | Replaced | The primary moves from the word to the tile; the word is set like any name |
| UIDR-045 rule 5 — one inset surface, hairlines | Broken | Units 6px apart on the page ground; a hairline between two pictures is a third picture |
| Direction 4's lead scrim (to the top) | Dropped | The seat sits on ink under .97 (A2) |
| Direction 1's right-edge vignette | Dropped on the band; kept on the lead at .30 | Nothing sits at the band's right edge; the lead's time does — the device C named for that seat |
| Direction 1's 58ch review measure | Bent on the band | 53ch so every line ends at the text zone's edge, where the time is |
| `.mono` tint at 15%; `--p` for the own fill | Bent | 18% + a 1px inset ring over 13% ink; the 62% button primary so a white initial has contrast |

## The one thing I am least sure of

The two picture origins at 1920: the lead's still begins at x=576, the bands' at 920, so the column's picture edge steps right 344px after the first unit. In the render it reads as the lead being larger in every dimension; it could read as two rules. If the owner sees the second, state 14 is the alternative, at the cost of the second subject on every still rendered.
