# C · Cross, capped — reasoning

Deliverable: `index.html` (links `../base.css`, art from `../art/`). Rendered with `page-shot` at 1920×1080 three times (the first pass exposed a width bug — an absolutely positioned `<img>` with `width:auto` takes its intrinsic aspect instead of stretching — the second and third tuned the scrims), once each at 1280×800 and 2560×1440, plus per-state clips at a tall viewport. One alternative was tried and rejected against the render (a 560px dissolve; below). Written from what is built.

## Style

One language at two sizes. The newest action in the scoped window is the **lead**: 1820×340 at 1920, its backdrop full-bleed under a two-layer scrim, the poster at 160×240, the title at 32px. Every other action is a **band**: 1820×152, its backdrop in a **900px box right-aligned in the band**, the box's left edge dissolving over 360px into the band's ink. Both are one markup — `.entry` with `.lead` or `.band` — and every position, size and alpha is a custom property of the size class. Left to right on both: the identity tile, the poster, the text block (sentence · title and year · review), the toolbar seat at the text block's foot, the time at the text zone's right edge, the picture. No border, glass, shadow or padding box on either: the unit is the image's edge and the ink the text needs.

Colour is the artwork's own plus three signals: the rose heart, the primary (own tile, cursor ring, tab underline, pill), nothing from the health palette. System fonts, dark only, no JavaScript.

## Every size, alpha and gap

**Frame.** Sidebar 52px; `main` padding 24px; `.content{max-width:none}` → 1820px at 1920, 1180 at 1280, 2460 at 2560. Tab strip: tabs 14px, the house `.seg` pill on the strip's line at the right, one hairline under both. Units 6px apart, lead included.

**Two constants shared by both sizes.** `--tz: 576px` — the text zone's right edge: the time's right edge and the band's measure end. `--box: 900px` — the band's image box cap.

**Lead.** 340 tall, radius 14. Tile 48px at x=32, its centre on line 1's centre (top 50). Poster 160×240 at (100, 50), radius 8, shadow `0 10px 28px` black/55. Body from x=280 to 800 (520px ≈ 58ch at 16px), 11px top padding so line 1 centres on the tile. Line 1: 18/26 at 80%, name 500 at 96%, glyph 16px. Line 2: 32/38 semibold at 100%, year 15px at 60%, 2px above, `drop-shadow(0 2px 10px)`. Line 3: 16/24 at 78%, three lines, 10px above. Time: 13/26 at 78%, right edge at 576, top 61. Seat: 20px at y 270–290 (the poster's foot). Scrim, two layers in the base hue `oklch(13% 0.02 264)`: to the right `.88 0 → .82 26% → .50 46% → .10 68% → 0 88%`; to the top `.35 0 → 0 40%`. Slice: the still scaled to 1820×1024, 340 visible → **33%**.

**Band.** 152 tall, radius 10. Tile 40px at x=18, centred on the band (top 56). Poster 72×108 at (74, 22), shadow `0 3px 12px` black/55. Body from 164 to 576 (412px ≈ 53ch at 14px). Line 1: 15/22 at 80%, name 500 at 96%, glyph 13px, 64px right padding so it ellipsizes before the time. Line 2: 18/24 semibold, year 13px at 60%, 1px above. Line 3: 14/20 at 78%, two lines, 5px above. Time: 13/22 at 78%, right edge at 576, top 22. Seat: 20px at y 110–130. **Image box**: left edge `max(576px, 100% − 900px)` → x=920 at 1920 (900 wide), 576 at 1280 (604 wide), 1560 at 2560 (900 wide); mask `transparent → #000 over 360px`. Scrim, pixel-anchored from the box's edge `bx`: `.97 0 → .93 bx → .55 bx+180 → .16 bx+360 → .04 bx+540 → 0 100%`. Slice: 900×506 scaled, 152 visible → **30%** (45% at 1280's 604px box). Ink between the text zone and the box: **344px at 1920**, 0 at 1280, 984 at 2560.

**Hover.** `--s: .8` multiplies every scrim alpha; the ground lifts 13% → 16%; both instant. The seat fades in over 120ms — the page's only transition. Height constant.

**Crop rule.** `object-fit: cover; object-position: 50% 30%` on every backdrop, lead and band. The second of two adjacent units of one title carries `.alt` → `50% 38%`. No per-title value anywhere; the generator that emitted the rows derives `.alt` from adjacency alone.

**Tile.** Monogram: primary at 18% with a 1px inset ring at 22% and `0 2px 8px` black/35; the initial 16px (40) / 19px (48) at 600 in the text primary. Own: `oklch(62% 0.16 264)` fill (the theme's button primary, not the 72% text primary), the initial `oklch(96% 0.008 264)` at 700. Photo: a portrait crop of a still (`one-step-beyond-backdrop.jpg`, 167×94 at −63/−15 in the 40px tile), 1px inset ring white/18. Own with a photo: the photo inside a 2px ring of the same button primary.

**Toolbar.** 13px at 78%; verbs 20px tall, 6px padding, 6px radius, 10% fill on hover; Ignore last with a 10px gap; plain states at 66%; Downloading's 3px hairline at `--pct`; no Delete.

**Cursor.** A 2px primary ring as the unit's top layer (`::after`, inset 0, radius inherited) — an outline on the unit paints under the positioned picture.

**No artwork.** Ground `--glass-inset-bg`, scrim `.35 → 0` over 800px, the poster slot as `.poster-empty` with a 1px white/6 edge, same box (152 / 340), text as on any unit.

Lowest read text: the year at 60% (plain states 66%; base.css's tab counts 60%). The 55%s on the page are base.css's `.state` labels — mockup scaffolding, not the design.

## Decisions

1. **The box is capped at 900 and right-aligned; the text zone is fixed at 576.** MEASUREMENT's sweep put a fixed 30% position at zero failures in a 900px box; the cap holds that slice at any width ≥ 1476. Below that the box shrinks from its left to the text zone's edge (1280: 604px, a 45% slice). The band therefore has three regions at 1920 — words 0–576, ink 576–920, picture 920–1820 — and the ink is this setting's cost, argued below.
2. **The time stands at the text zone's edge on every unit, the lead included.** BRIEF-5 gives C "time at the text zone's edge, as B" and "lead as A"; A's lead puts its time top-right. I read the first as C's setting for the time question and applied it to both sizes, and I name that as a bend of "lead as A" (below). What it buys: one vertical axis of times at x=576 down the whole column, the lead's included, 1,200px closer to the words than the lead's corner; and the lead's top-right corner — its clearest picture on a 33% slice — stays picture, with no vignette to carry a timestamp. What it costs: on the lead the time sits at line 1's right *inside* the lead's wider text block (the title and review run to 800 beneath it). It read as a byline's timestamp in the render, not as a stray; but see the least-sure item.
3. **Ink between the words and the picture.** Honest answer: **at 1920 it reads as a gutter, not a hole; at 2560 it is a hole.** What makes it a gutter at 1920 is two things I did on purpose. The times are right-aligned to one x, so the text zone has a hard right edge and everything right of it is the picture's territory; and the picture's dissolve is long and starts within 350px of that edge, so the still's dark side — Grant's ghosted face on the Charade bands — creeps toward the words and the flat ink reads as the deep end of the same gradient. What I tried and rejected: a 560px dissolve with a slower scrim, which shortened the flat ink but smeared the emergence and cut the clear picture to ~340px; and I considered widening the measure to 640 (28px less ink for a 60ch measure at 14px — not worth the axis moving) and a tonal lift of the ink toward the picture (a 2% ramp over 344px is imperceptible; a stronger one is a glow, which is direction 5's device). On listing rows the dark is wider still (the words end near x=350) and the time at 576 is the only mark in it; the same is true of A and D at 560. At 2560 the ink is 984px and no dissolve rescues it; the app's UI scale renders a 2560 panel at ~1920 CSS px, so the 1× case is the forced-scale edge, but it is real and I would not ship this setting to a user who pins the scale down on a wide panel without B's container or A's box.
4. **The scrim ramp clears the box's centre.** The first tuned pass ramped over bx+240/480/700 and left the box's horizontal centre (x≈1370, where a still's subject usually sits) under a .16–.3 scrim — Big Buck Bunny's face was dimmed while Hepburn, off-centre, was clear. The shipped ramp (bx+180/360/540) puts the centre at ≈ .08. The clear picture is ~520px at 1920, direction 1's width.
5. **The lead's ramp clears earlier than direction 4's.** Direction 4: `.78 30% → .42 55% → .06 78%`. At 1820 that put Sintel's near eye under .45. The lead's stops here are percentages (the lead is full-bleed and its text zone relation holds at any width): `.82 26% → .50 46% → .10 68% → 0 88%`. The review's measure ends at 800 (44%), over ≈ .55 with the text shadow — legible in the render.
6. **The tile sits on line 1 on the lead, on the centre on the band.** Direction 1 centred it on the band (line 1's centre is 33px from the band's top; a 40px disc there hangs in the corner). Direction 4 centred it on line 1 (on a 240px body, a centred disc would float beside the empty middle of a listing). Both are `--tile-top`, one property of the size class; the rule is "the tile marks the byline on the lead and the row on the band".
7. **The poster at 160×240 on the lead, 72×108 on the band.** 240 is 71% of 340 as 220 was 73% of 300 in direction 4; 50px above and below. The band's is direction 1's.
8. **"You" is neutral.** The filled tile is the own mark; the word is the grammar. One signal per row.
9. **No right-edge vignette on the band.** Direction 1's `.48 → 0` over 220px existed for a time seated there. Nothing sits there now, so the picture's right edge is the band's rounded edge, as Home's cards.
10. **Own with a photo** keeps the mark as a 2px ring of the same button primary. Nothing else changes.
11. **The lead's scrim is the same recipe hovered**: `--s` multiplies both layers, so the lead and the band step the same way.
12. **Show older, empty state, tab strip, glyphs, modal**: as direction 1 and as round 4's brief.

## Requirements mapping

| Brief item | How it is met |
|---|---|
| Flat, newest first, one entry per action; size is position | Index 0 of every strip is `.lead`, the rest `.band`; no grouping, no re-sort; the generator assigns size by index only |
| One anatomy, one markup with a size property | `.entry.lead` / `.entry.band`; identical children in identical order; sizes are custom properties |
| Tile · poster · text block · seat · time · picture, left to right | Both sizes, positions above |
| Identity tile: monogram, photo, own = button primary + white initial; "You" neutral; own+photo = 2px ring | Tiles on every unit; Ada's photo in state 8; the own photo in 8 · continued; "You" at 500/96% |
| Crop rule: `50% 30%` everywhere, `50% 38%` on the second adjacent | `.entry .bd{object-position:50% 30%}`; `.entry.alt .bd{50% 38%}`; no inline positions; rows 3 and 7 in state 1, row 2 in state 10 carry `.alt` |
| Band scrim: direction 1's recipe, pixel stops, ×.8 on hover, ground lifts | `.band .scrim`, `--s`, `.entry:hover` |
| Lead scrim: direction 4's two layers, same hue | `.lead .scrim` |
| Toolbar contract | 20px seat at the poster's foot on both sizes; friend List · Download · Ignore; own List · Download; plain states; no Delete; height constant |
| Scope pill, tab strip, counts, entry rule, glyphs, empty state | As direction 1; Feed 16 · 11 · 5; count omitted at zero |
| State 1 Everyone + Show older | `#f1`: lead Cleo · Sintel, fifteen bands, ghost Show older |
| State 2 Friends | `#f2`: lead Cleo · Sintel; bands Nick · Charade, Nick · Metropolis, Bob · Pioneer One, Sam · Big Buck Bunny, Ada · Night of the Living Dead |
| State 3 You | `#f3`: lead You · Charade (a review), bands Big Buck Bunny, Tears of Steel, The General, Sprite Fright; five filled tiles |
| State 4 You, empty | Headline, body, one ghost action; count omitted |
| State 5 friend hovered | `#f5` Nick · Metropolis band; `#f5b` Spring (Tracking · Download · Ignore), Pioneer One (List · In library · Ignore), Charade (Listed · In library · Ignore); `#f5c` the lead hovered |
| State 6 own hovered | `#f6` You · Charade: Listed · In library; `#f6b` Tears of Steel: List · Downloading with the hairline |
| State 7 cursor | `#f7` Nick · Charade: 2px ring, seat shown |
| State 8 photo | `#f8` Sam (monogram), Ada (photo), You (own); `#f8b` You with a photo in the ring |
| State 9 no artwork | `#f9` Femi · Coffee Run band |
| State 10 lead as a review with words | `#f10`: a second Everyone strip of four — lead You · Charade (three-line review at 16px), then Nick · Charade at 38%, Nick · Metropolis, Bob · Pioneer One. The You scope (state 3) shows the same lead |
| State 11 lead with no artwork | `#f11` Cleo · The Cabinet of Dr. Caligari, 340px inset box, empty poster at 160×240 |
| State 12 adjacent bands, 8% offset | `#f12` rows 2–3 Charade at 30% / 38% |
| State 13 hovered band, scrim step and seat | `#f13a` at rest, `#f13b` hovered, Nick · Cosmos Laundromat |
| Eager images (UIDR-012) | Plain `<img>`, no `loading` |
| Text ≥ 55%; no chips, badges, bars, dividers, group headers, animation, light theme, real titles beyond `art/` | None; year 60% is the floor for read text; one 120ms fade |
| No JavaScript | None; `.hovered` and `.cursor` are static classes |

## The time seat, argued

Four candidate seats: the band's far right (A, direction 1: 1,700px from the words, needing a vignette); the text zone's edge (B, C: x=576, on line 1, one axis); the seam where the picture begins (x≈920 here — "before the picture begins" in B's words, but in C that is not the text zone's edge); the lead's corner (A's lead). This page takes the text zone's edge on both sizes. The axis is the argument: sixteen times at one x down the column, read in one saccade, the lead's included. The cost is stated in decision 2. If the owner wants A's corner on the lead, it is one property (`right` on `.lead .when`) and the lead's top-right needs a `to left` vignette of about .4 over 220px to hold the 13px text on a bright still.

## What a new arrival does

The new action becomes the lead; the old lead becomes band 1 — its picture goes from a full-bleed 340 to a 900px box at 152, its title from 32px to 18 — and everything below moves down 158px (one band plus the gap). The lead's box is fixed, so the top of the page keeps its height; the shift is the same one-row shift the shipped list produces for a reader scrolled into it. The adjacency offset re-evaluates on render: an arrival between two units of one title removes the `.alt` from the second (both at 30%), an arrival of the same title as the current lead puts `.alt` on the old lead as band 1. Nothing animates. A scope change re-projects from the newest action in scope: under You the lead is You · Charade.

## At 3 and at 300

At 3: the lead and two bands, 656px, no Show older. At 1: the lead alone under the strip. At 300: 340 + 299 × 158 ≈ 47,600px; the fixed left spine (tile, poster, sentence, time at the same x on every band) is what holds it, and Show older pages the window to 16–32 units, so 300 is never one render. Eager backdrops at `?w=1280` cost about 150KB each, paged.

## Width, and the Watchlist and Friends tabs

Full width, Home's opt-out. The strip and its hairline span the container with the pill at the far right; the Watchlist and Friends tabs share the strip, the h1 and the left edge and keep their card grids, which gain columns at 1920 and lose them at 1280 — the same relation Home has to the Library.

## 1280 and 2560

**1280×800**: units 1180 wide. The band's box is 604px from x=576 (a 45% slice — squarer, whole faces: Sintel's dragon, Hepburn and Grant both); no ink at all, the picture emerging right after the time column. The lead's percentage stops keep its text zone at ≥ .8 and Sintel's face clear. The pill fits the strip. This is the setting's best case.

**2560×1440**: units 2460 wide. The lead holds (full-bleed, the eyes centred). The band's box stays 900 (the 30% slice is the point), so the ink is 984px and reads as a hole between the times and the still. The app's UI scale (screen ÷ 1920 × preference) renders a 2560 panel at ~1920 CSS px, so this is the forced-scale case; it is the honest limit of a capped box on a wide page.

## Standing rules: kept, bent, broken

| Rule | Status | Exception, precisely |
|---|---|---|
| UIDR-038 rule 2 — flat, newest first, one entry per action | Kept | Size is index 0 vs the rest; nothing merged or re-sorted |
| UIDR-038 rule 3 — one anatomy | Kept | One markup; `.own` changes the tile's fill only; `.lead` / `.band` change sizes only |
| UIDR-033 — artwork when it is the subject | Kept | Every unit shows only its own title's poster and backdrop |
| UIDR-038 *wall of watching* | Bent | The page is half picture. Exception: every unit leads with a sentence about a person in a fixed 576px text zone; the picture is the row's own title, after the words |
| UIDR-038 *title-first row* | Bent (lead only) | The lead's title is its largest type (32px) under an 18px sentence; reading order is still tile, sentence, title. Bands keep 15/18 |
| UIDR-038 *social-network chrome* | Bent | The identity tile is the Friends tab's monogram; the photo slot is the owner's note; no handles, counts, reactions |
| UIDR-038 *hover jump*, *grouped rows*, *state as decoration*, *day dividers* | Kept | Heights constant; no groups; state only as seat words and the hairline; no dividers |
| UIDR-045 rule 3 — own = "You" in the primary | Replaced | The primary moves from the word to the tile; the word is set like any name |
| UIDR-045 rule 5 — one inset surface, hairlines | Broken | Units 6px apart on the page ground; a hairline between two pictures is a third picture |
| UIDR-045 toolbar contract | Kept | Same slots, states, seat; Ignore last; no Delete |
| Colour is signal | Kept | Primary = own tile + interaction; rose = love; the artwork's colour is the artwork's |
| Text ≥ 55% | Kept | Year 60%, plain states 66%, everything else ≥ 78% |
| 120ms toolbar fade is the ceiling | Kept | The scrim step and ground lift are instant |
| MEASUREMENT's crop rule | Kept | `50% 30%` everywhere, `50% 38%` on the second adjacent, no per-title values |
| BRIEF-5 "lead as A" | Bent | The lead is A's 1820×340; its time is not at A's top-right but on the page's one axis at x=576 (decision 2) |
| BRIEF-5 "the tile … left to right on both" | Kept, with a per-size vertical | Band: centred on the band. Lead: centred on line 1 (decision 6) |
| Direction 1's 58ch review measure | Bent | 53ch (412px) on the band so every line ends at the text zone's edge, where the time is |
| Direction 1's right-edge vignette | Dropped | Nothing sits at the band's right edge now |
| `.mono` tint at 15% | Bent | 18% + a 1px inset ring at 22% over 13% ink, as direction 1 |
| `--p` for the own fill | Bent | The theme's button primary (62% / 0.16) so a white initial has contrast; `--p` (72%) stays the text primary |

## Trade-offs

- **The ink.** 344px of dark at 1920 between the time column and the picture; a gutter by the devices in decision 3, a hole at 2560. A's box from 560 has no ink and a 21% slice; B's container has no ink and a 37% slice inside 1280. This setting buys crop safety and full-width presence with that band of nothing.
- **Listing rows are mostly dark.** Two short lines, the time, then ink to the picture. The constant seat and the fixed text zone are worth more than a tighter listing; the poster and the tile carry the row.
- **The lead's time sits inside its own text block's width.** One axis for the page against A's corner; stated in decision 2.
- **Two adjacent units of one title still show one still twice** — at two positions now (30% / 38%), which reads as two frames of a scene rather than a repeat; it is still the same scene.
- **The clear picture is ~520px of a 900px box.** The rest is the dissolve. A shorter dissolve makes the box's edge a wall; a longer one (tried at 560) makes the clear part a sliver.
- **The lead swaps wholesale on every new action** and demotes to a band; the type and the picture change size in place. Fixed boxes keep the top of the page from moving.
- **Six units per fold** at 1080 (the lead and four and a half bands) against nine shipped rows.
- **Eager backdrops** on a page that already loads posters; paged by Show older.

**What I would change with the others' settings.** With A's: start the box at 576 and accept the 21% slice; the times could then stay at the text edge (A puts them far right; the axis argument holds there too). With B's: the same page inside 1280, no ink, the 604px box everywhere. With D's: a 200px band for reviews with words would take the review to three lines at 15px and give the ink zone on review rows more words to fill it; the listing rows would still be dark.

## The one thing I am least sure of

Whether the ink reads as composed or as a hole to the owner at 1920. I have argued it as a gutter because the time column gives the text zone a hard edge and the dissolve reaches back toward it, and the render supports that on review rows; on listing rows the band is words, a lone timestamp, 400px of dark, then a picture, and I can see it read as a hole. The second doubt, smaller: the lead's time at x=576, inside the lead's wider text block rather than at its corner.
