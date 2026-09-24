# A · Cross, full width — reasoning

Deliverable: `index.html` (links `../base.css`, art from `../art/`), no JavaScript. Rendered with `page-shot` at 1920×1080 three times (the fold, a 2700px-tall pass over state 1, a 2900px pass to "Show older"), once each at 1280×800 and 2560×1440, plus per-state clips for states 3–13 and a 1:1 crop of the lead's type. Written from what is built. The page was generated from the round's data table by a scratch script (not committed) so that the crop offset is computed from adjacency and never typed by hand.

## What it is

One unit at two sizes. Index 0 of the scoped window is the **lead**: 1820×340 at 1920, the title's backdrop full-bleed under direction 4's two-layer scrim, the poster at 160×240, the sentence at 18px, the title at 32px, the identity tile at 48px. Every unit after it is a **band**: direction 1's 152px row, the backdrop from x=560 to the right edge under the left-weighted scrim, the poster at 72×108, the tile at 40px. One markup (`.u`) for both; `.lead` and `.band` set only custom properties (height, radius, image box origin, padding, tile, poster, the x of the poster and the text, the time's inset, line 1's height). Left to right on both: tile, poster, text block with the seat at its foot, the time at the right. 6px between units and no container: the lead is the first unit of one column, not a tier above it. No border, glass or shadow on either size — the unit is the image's edge, as direction 1's band was; direction 4's glass border on the lead is dropped.

Colour is the artwork's own plus three signals: the rose heart, the primary (the own tile, the cursor ring, the tab underline, the pill's chosen option), nothing from the health palette. System fonts, dark only.

## Every size, alpha and gap

| | Band | Lead |
|---|---|---|
| Unit | 1820×152 at 1920, radius 10 | 1820×340, radius 14 |
| Ground | `oklch(13% 0.02 264)` (base-100); hover 16% | same |
| Image box | x=560 → right edge (1260×152 at 1920); left edge dissolved by a mask, transparent → opaque over 320px | full-bleed (1820×340) |
| Slice of the still at 1920 | 1260 → 709px tall: **21%** | 1820 → 1024px tall: **33%** |
| Crop | `object-fit: cover; object-position: 50% 30%`; `.off` (the second of two adjacent units of one title) `50% 38%` | same |
| Scrim, to the right (× `--s`) | .97 at 0 · .93 at 540px · .55 at 800px · .16 at 1060px · .06 at 1260px | .88 at 0 · .80 at 600px · .46 at 980px · .10 at 1400px · 0 at 1820px |
| Scrim, to the top (× `--s`) | — | .35 at the foot → 0 at 40% |
| Vignette, to the left (× `--s`) | .55 → 0 over 240px | .30 → 0 over 220px |
| Hover | `--s: .8` (every scrim alpha × .8), ground 13% → 16%, both instant | same |
| Padding (top = poster top = tile top = text top) | 22 | 50 |
| Tile | 40px at x=18; initial 16px | 48px at x=28; initial 19px |
| Poster | 72×108 at x=74; radius 6 (base); shadow `0 3px 12px` black/55 | 160×240 at x=94; radius 8; shadow `0 10px 28px` black/55 |
| Text block | from x=164, height 108, right inset 130 | from x=276, height 240, right inset 150 |
| Line 1 | 15/22 at 80%; name 500 at 96%; glyph 13px | 18/26; glyph 16px |
| Line 2 | 18/24 600 at 100%; year 13px at 60%, 9px gap; 1px above | 32/38; year 15px at 62%, 10px gap; 2px above; `drop-shadow(0 2px 10px)` |
| Line 3 | 14/20 at 78%, two lines, 58ch, 5px above | 16/24 at 78%, three lines, 58ch, 10px above |
| Seat | 20px at the text block's foot (y 110–130 in the band) | 20px at the text block's foot (y 270–290 in the lead) |
| Time | 13/22 tabular at 72%, right 20, top 22 | 13/26 at 72%, right 28, top 50 |
| Text shadow | `0 1px 3px` black/85 on the block; `0 1px 3px` black/90 on the time | same |
| Toolbar | verbs 13px at 78%, 14px icons, 6px padding, radius 6, 10% fill on hover; Ignore last with a 10px gap; plain states at 66%; Downloading's 3px hairline at `--pct` | same |
| Cursor | 2px primary ring, `::after` at inset 0, following the radius, z above the image and scrim | same |
| Gap between units | 6px | 6px |

**Tile.** Friend: `.mono` at 18% primary fill with a 1px inset ring at 22% and a `0 2px 8px` black/35 shadow (base's 15% vanishes on 13% ink). Own: `oklch(62% 0.16 264)` (the theme's button primary) with a white initial at 700. Photo: the image clipped by the circle, a 1px inset ring at white/18. Own with a photo: a 2px ring of the same 62% primary outside the circle.

**Tab strip.** Zone tabs at the left, the house `.seg` pill on the same line at the right (6px above the strip's hairline), one hairline under both spanning the full width. The count follows the scope: Feed 16 · 11 · 5; omitted at zero.

**Lowest read text**: the year at 60%. Plain states 66%. The `.keys` labels at 55% are mockup scaffolding.

## Decisions

1. **The lead's image is full-bleed; the band's box starts at 560.** The brief fixes the lead at 1820×340 for a 33% slice, which is the full-bleed figure; the band inherits direction 1's box (a 21% slice; under a 97% scrim the left 560px would contribute nothing). So the two sizes crop differently on purpose: the lead shows a third of the still with its left under a colour cast, the band a fifth with its left in ink. Both obey the one position.
2. **The lead's scrim stops are pixels, not percentages.** Direction 4's recipe (heavy left, a foot dim) is kept; its percentage stops are re-anchored in pixels — .88 → .80 at 600px → .46 at 980px → .10 at 1400px → 0 — so the text zone is the same at 1280, 1920 and 2560, the principle direction 1 set for the band. The stops sit further right than the band's because the lead's text runs from x=276 to about 780 (a 58ch measure at 16px); the first pass was a step darker (.90/.84 to 700px) and the lead's left was a void; this step leaves a colour cast under the words.
3. **Tile, poster and text share a top edge, at both sizes.** Direction 1 centred the tile on the band; direction 4 centred it on line 1. One rule for two sizes: the tile's top is the poster's top is the text block's top (22 on the band, 50 on the lead). The 40px tile then brackets line 1 and the top of line 2; the 48px tile does the same on the lead. It reads as a chat client's avatar — the mark of the message's head — and gives every unit a flush top edge. A tile centred on a 340px lead would sit beside the poster's middle, 120px from the name.
4. **One gap, 6px, lead included.** Direction 4 put 16px under its lead; here the lead is the column's first unit, and the gap says so. The lead's radius (14) against the band's (10) is the only edge difference.
5. **No frame on the lead.** Direction 4's lead carried the glass border and shadow; the band carries nothing, and one language means the lead carries nothing either. The image's edge is the unit's edge.
6. **The identity tile is the author mark; "You" is neutral.** The own fill is the theme's 62% button primary with a white initial (the 72% text primary would not carry a white letter); the word "You" is 500 at 96% like any name. Two own signals on one row would say one thing twice.
7. **The photo state is a stand-in.** The tile's photo is a circular crop of a backdrop from `art/`, sized and offset by hand inside the 40px circle so a face fills it. This is not a backdrop crop and is not subject to the crop rule: a published photo arrives already framed as a portrait; the mockup fakes one from a still because no other image source is allowed.
8. **Hover is instant except the toolbar.** Direction 4 transitioned the scrim's opacity over 120ms; the critique read the ceiling as one duration rather than one element. Here `--s` steps and the ground lifts with no transition; only the toolbar's opacity fades, 120ms.
9. **The vignette rides `--s` too.** Direction 1 fixed the band's vignette at .48; here every scrim alpha, the vignette's included, multiplies by `--s`, so hover is one operation. The band's vignette is deeper (.55 over 240px) because "3d ago" over Big Buck Bunny's sky was faint at .48.
10. **The lead's poster is 160×240 at 50px padding, not 173×260 at 40.** Tried both against the render. The larger poster crowds the lead's top and bottom edges and pushes the text to x=289; the smaller one leaves the still room above and below and reads as a card standing on a photograph.
11. **The crop offset is computed.** Inside a strip, a unit whose title matches the unit before it takes `.off` (38%). In state 1 that is row 3 (Charade, after row 2) and row 7 (Big Buck Bunny, after row 6). Under Friends nothing is adjacent; under You nothing is. State 13 repeats one row as a rest/hover pair and is exempt: it is one row drawn twice, not two actions.
12. **The seat is at the text block's foot, which is the poster's foot.** On a listing lead the seat is 140px below the title; on a band, 66px. The constant seat is worth more than a tighter listing.
13. **The no-artwork unit** is the inset tone (`--glass-inset-bg`) at the unit's height with a .35 → 0 scrim over 800px, the poster slot as `.poster-empty` with a 1px white/6 edge, the text as on any unit. A no-artwork lead is 340px of that: honest, rare (a freshly listed title whose backdrop is still warming), and the fixed height means the page does not jump when the art arrives.

## Requirements mapping

| Brief item | How it is met |
|---|---|
| Flat, newest first, one entry per action; size is position | `strip()` renders index 0 as `.lead`, the rest as `.band`; no re-sort, no merge, no promotion for words |
| One anatomy, one markup with a size property | `.u` + `.lead` / `.band` custom properties; identical child markup (`.bd .scrim .tile .poster .body .when`) |
| Identity tile: monogram / photo / own filled 62% with a white initial / own photo in a 2px ring | Every friend row; Ada in state 8; every own row; You in state 8 |
| "You" set like any name | `.who` 500 at 96% on own rows; the tile is the mark |
| Crop rule: `50% 30%` everywhere; `50% 38%` on the second of two adjacent rows of one title; no per-title positions | `.u .bd{object-position:50% 30%}`; `.u.off .bd{object-position:50% 38%}`; no inline `object-position` anywhere |
| Band scrim = direction 1's recipe; hover × .8 and a ground step; nothing else moves | `.u .scrim` stops verbatim; `.u:hover,.u.hovered{--s:.8;background:16%}`; 152px at rest and hovered |
| Lead scrim = direction 4's two layers in the base hue | `.u.lead .scrim`: to the right + to the top, `oklch(13% 0.02 264)` |
| Toolbar contract unchanged | 20px seat at the block's foot; friend List · Download · Ignore; own List · Download; no Delete; states 5, 5 · continued, 6, 6 · continued |
| Scope pill, tab strip, entry rule, glyphs, empty state | As direction 1: the pill on the strip's line at the right; round 3's sprite; the You-empty copy |
| Full width; lead 1820×340; bands 152 from x=560; time far right on bands, top right on the lead | `.content{max-width:none}`; `--h`, `--img-x`, `--wr` per size |
| State 1 Everyone + Show older | `#f1`: lead Cleo · Sintel, fifteen bands, `.off` on rows 3 and 7; ghost "Show older" on the tile's edge |
| State 2 Friends — first six, own gone | `#f2`: lead row 1; bands 3, 4, 5, 7, 8; Feed 11 |
| State 3 You — five own rows | `#f3`: lead row 2 (a review), bands 6, 9, 13, 16; every tile filled; Feed 5 |
| State 4 You, empty | Headline 17/600, body 14 at 70%, one ghost "Settings → Social"; count omitted |
| State 5 friend's row hovered | `#f5`: the lead hovered, List · Download · Ignore seated; `#f5b`: Tracking, In library, Listed (filled) on bands |
| State 6 own row hovered | `#f6`: You · Charade, Listed · In library; `#f6b`: You · Tears of Steel, List · Downloading with the hairline |
| State 7 cursor | `#f7`: Nick · Charade, the 2px ring on the band's top layer, toolbar shown |
| State 8 friend with a photo | `#f8`: Sam (monogram), Ada (photo), You (photo in the primary ring) |
| State 9 no artwork | `#f9`: Femi · Coffee Run as a band |
| State 10 lead as a review with words | `#f3`'s lead (own: You · Charade) and `#f10`: a second Everyone strip led by Ada · Night of the Living Dead (two lines at 16px) over rows 9–11 |
| State 11 lead with no artwork | `#f11`: Cleo · The Cabinet of Dr. Caligari, 2m ago, the inset tone at 340px |
| State 12 adjacent bands of one title | `#f12`: rows 2–3, Charade at 30% then 38% |
| State 13 a band hovered | `#f13`: Nick · Metropolis at rest, then hovered |
| UIDR-012 eager images | Plain `<img>`; no `loading` attribute |
| UIDR-033 | Each unit shows only its own title's backdrop and poster |
| No chips, badges, bars, dividers, group headers, entrance animation, light theme, real titles beyond `art/`, text < 55%, hover height change, JavaScript | None present; one 120ms opacity transition on the toolbar |

## The width, and what the Watchlist and Friends tabs do

Full width (`.content{max-width:none}`, Home's opt-out): units 1820px at 1920. The lead spans the monitor; the band's still runs from 560 to the edge. The tab strip and its hairline span the same width with the pill at the far right. The Watchlist and Friends tabs share the strip and the left edge and keep their cards; their grids gain columns at 1920 and lose them at 1280. What is constant across the three tabs is the strip, the h1 and the left edge; what fills the width differs by tab, as it does between Home and the Library.

Below 1280 the band's text zone is fixed at 560px and the image box shrinks from its left; below about 900px the box is the mask alone. The lead keeps its text zone and loses clear image from the right. The page is not designed under 1280.

## The time's seat, argued

The band's time is at its far right over the vignette; the lead's at its top right, on line 1's height. At 1920 that is about 1,650px from the words on a band and 1,540px on the lead. The argument for it: the right edge is the page's time axis — a column of small figures at one x on every unit, lead and band alike, read by a scan down the edge the way the left edge is scanned for authors. It is an orientation, not part of the sentence; the sentence has the name, the verb and the title, and the time sits where the shipped list's column sat. The vignette makes it legible over a bright still (state 1, Big Buck Bunny) without darkening the picture's subject.

The alternative, B's seat at the text zone's edge (x≈540 on line 1's height): closer to the words, in the ink, off the picture. What I would change with that setting: the time on the lead would sit at x≈540 in the lead's dark middle, beside nothing — the lead would want it top right regardless, and the two sizes would then seat the time differently, which is the thing this cross is trying not to do. The far-right seat is the one seat that is the same rule on both sizes.

## A new arrival

The lead swaps in place: its image, tile, sentence, title and text change; its box (1820×340) does not. The old lead re-renders as band 1 — its still re-cropped to the band's 21% slice at the same 30%, its poster 160 → 72, its title 32 → 18 — and every band below moves down 158px (one band plus the gap), the same one-unit shift the shipped list produces for a reader scrolled into it. If the arrival's title matches the old lead's, band 1 takes `.off` and shows the 38% frame. Nothing animates. Compared with direction 4, whose fixed boxes let the ramp re-project with nothing moving, this page moves the column by one band; the price of one size instead of three.

A scope change re-projects from the newest action in scope: under Everyone and Friends the lead is Cleo · Sintel; under You it is You · Charade, a review, so the lead carries line 3.

## At 3 and at 300

Three: the lead and two bands, 656px under the strip, no Show older. A photograph with a headline and two captioned stills is a composition, not a sparse list.

Three hundred: 340 + 299 × 158 ≈ 47,600px. What holds it is the fixed left zone — tile, poster, sentence at the same x on every band — and the pictures changing on every band. "Show older" pages the list, so a window is 16–32 units. Cost: one backdrop per unit, eager. The band's derivative is `?w=1280` (about 150KB); the lead's box is 1820px wide, so the lead needs a `?w=1920` derivative (about 300KB) — one more tier than direction 1 asked for.

Rows per fold at 1920×1080: the lead and about 3.7 bands on the first screen, 6.8 bands on every screen after.

## The 1280 and 2560 checks

**1280×800.** Units 1180px. The lead's still is 664px tall — a **51%** slice, Sintel's whole face and the dragon's head. The band's box is 620px and the still 349px — a **44%** slice, whole faces. The lead's scrim at its right edge is about .30 (the pixel stops do not reach 0 inside 1180), so the picture never fully clears; the band's box sits under the .93 → .16 ramp, so its picture reads in its last 400px. The text zone, tile, poster and type are identical to 1920. The fold shows the lead and one band plus half of the next. Holds; the lead is at its best here.

**2560×1440.** Units 2460px. The lead's still is 1384px tall — a **25%** slice; the band's box 1900px and the still 1069px — a **14%** letterbox. Sintel's eyes and Hepburn's eyes still land because 30% aims at the upper third; Metropolis is rings and a torso. The text zone stays 560px; the time is 2,300px from the words. It holds as a cinema strip and gains no information. The app's UI scale (screen ÷ 1920 × preference) renders a 2560 monitor near the 1920 composition, so this raw check is the edge case.

## Standing rules: kept, bent, broken

| Rule | Status | Exception, precisely |
|---|---|---|
| UIDR-033 — artwork when it is the page's subject | Kept | Each unit paints only its own title's backdrop and poster; the page ground is the app's radial. |
| UIDR-038 rule 2 — flat, newest first, one entry per action | Kept | Size is index 0 versus the rest; no grouping, no re-sort. |
| UIDR-038 rule 3 — one anatomy | Kept | One `.u` markup; `.own` changes only the tile's fill; `.lead` changes only sizes. |
| UIDR-038 *wall of watching* | Bent | The page is two-thirds picture at 1920. Exception: every unit leads with a sentence about a person in a fixed text zone; the picture is the row's own title, after the words. |
| UIDR-038 *title-first row* | Bent, on the lead only | The lead's title is 32px over an 18px sentence. Reading order is unchanged — tile, sentence, title — and the band keeps 15/18. A front page's headline is the title. (Direction 4's exception.) |
| UIDR-038 *grouped rows*, *day dividers* | Kept | None. |
| UIDR-038 *state as decoration* | Kept | Colour is the artwork's own; added colour is the heart, the own tile and the cursor. |
| UIDR-038 *social-network chrome* | Bent | The identity tile is a person device. Exception: it is the Friends tab's monogram; the photo slot exists because the owner asked for a space; no handles, counts, reactions or links. |
| UIDR-038 *hover jump* | Kept | 152 and 340 at rest and hovered; the seat is in the fixed layout. |
| UIDR-045 rule 3 — own = the word You in the primary | Replaced | The primary moves from the word to the tile (62% fill, white initial; a 2px ring when a photo replaces the fill). "You" is set like a friend's name. |
| UIDR-045 rule 5 — one inset surface, hairlines between rows | Broken | Units 6px apart on the page ground, no container, no hairlines: a hairline between two pictures is a third picture. |
| UIDR-045 toolbar contract | Kept | Same slots, states and seat idiom; Ignore last; no Delete. |
| Colour is signal | Kept | Primary = own tile + interaction; rose = love; no health palette. |
| Round 3's *no card per entry* | Bent | The unit is a per-row surface. Exception: no border, glass, shadow, padding box or chrome on either size — it is the image's edge and the ink the text needs. |
| The 120ms toolbar fade is the ceiling | Kept | The only transition on the page. The scrim step and ground lift are instant. |
| `.mono` tint at 15% | Bent | 18% fill + a 1px inset ring at 22% over 13% ink, where 15% vanishes. Letter, size and hue unchanged. |
| `--p` for the own fill | Bent | The theme's button primary (62% / 0.16) for the fill so a white initial has contrast; `--p` (72%) stays the text primary. As the brief directs. |
| MEASUREMENT's crop rule | Kept to the letter | `50% 30%` on every backdrop; `50% 38%` on `.off`, computed from adjacency; no inline positions. |
| Direction 4's lead scrim | Bent | The two layers and the base hue are kept; the stops are pixel-anchored and moved right (decision 2). |
| Direction 4's lead frame (glass border, shadow, 16px below) | Dropped | One language: the lead is framed like the band, which is not at all, 6px above the first band. |
| Direction 1's tile seat (centred on the band) | Replaced | Flush with the poster's top at both sizes (decision 3). |
| Direction 1's fixed vignette (.48) | Bent | .55 over 240px, and it multiplies by `--s` with the rest of the scrim. |
| "No hand-set crops" | Kept for backdrops; the photo tile is a stand-in | The photo tile's image is hand-framed inside the circle (decision 7). It is a fake portrait, not a title backdrop. |
| Text ≥ 55% | Kept | Year 60/62%, plain states 66%, time 72%, verbs and review 78%, sentence 80%. |
| UIDR-012 eager images | Kept | No lazy loading. |

## Trade-offs

- **The fixed crop has visible costs on this page.** Metropolis at 30% is the robot's rings and torso, its head above the band; Charade at 38% (row 3, the offset) crops the crown. Both are what the rule does to these two stills at 21%; the poster beside them carries the title. The measured set (24 real backdrops) had none at 30% and the offset was judged safe; this art set has one marginal still at each. No hand-tuning was done and none should be.
- **The lead's subject can sit under the scrim.** Full-bleed, the still's centre is at x≈910, where the lead's scrim is about .5. Sintel and Night of the Living Dead put their subjects right of centre and read clearly; a still with its face dead-centre would be half-veiled. The band does not have this problem — its box starts at 560, so its subject lands at x≈1190, in the clear.
- **A listing lead has an empty middle** (y 130–270 on the left) because the seat is at the poster's foot. The still fills it; nothing is invented.
- **The column moves by one band on every arrival.** Direction 4's fixed ramp did not; the cost of one size instead of three.
- **The time is far from the words** at full width; argued above.
- **2560 is a letterbox** (14%); the app's UI scale makes it the edge case.
- **Bandwidth**: sixteen eager backdrops per page plus a `?w=1920` tier for the lead; paged by Show older.
- **Two lines of review on a band** at 152px; a long review is cut and lives in the modal. D's setting would grow the band for words; here every band is 152.
- **The own tile is 40px of solid primary on every fifth row** and 48px on an own lead; that is its job, in one hue, one shape, one seat.

## What I would change with the other directions' settings

- **B (1280, time at the text zone's edge):** the lead at 1280×300 would need the poster back at 147×220 and the stops at direction 4's positions; the band's 37% slice would rescue Metropolis and Charade. The time at x≈540 would want a different seat on the lead (see above).
- **C (capped 900px box):** the band's mask and the .93 → .55 ramp would have to end at the box's dissolved edge instead of running to 1260; the lead unchanged. I would expect the ink gap between text and picture to read as a hole under a full-bleed lead, because the lead has no such gap.
- **D (200px bands for words):** line 3 at 15px, three lines; the seat drops 48px on those bands and the time axis stays at the top edge, so the right column's rhythm breaks where a review is.

## The one thing I am least sure of

**The lead's image box.** I built the lead full-bleed because the brief's 33% figure is the full-bleed figure and direction 4's lead is what the cross inherits. But the band's box-from-560 is the better crop engine: on a 340px lead a box from 560 would show a **48%** slice (1260 → 709px tall, 340 of it) with the still's subject centred at x≈1190 in the clear zone, at the cost of the lead's left 560px being ink instead of a colour cast. That is a larger, safer picture with the same one rule, and it would make the lead literally the band at 340 — one image box rule as well as one markup. I did not build it because the brief set the lead's slice; it is the first thing to render if the owner finds the lead's left half too dark or its subject too veiled.
