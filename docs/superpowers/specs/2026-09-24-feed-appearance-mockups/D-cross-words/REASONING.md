# D · Cross, words — reasoning

Deliverable: `index.html` (links `../base.css`, art from `../art/`). Rendered with `page-shot` at 1920×1080 three times (pass 1 the build, pass 2 the lead's scrim, pass 3 the photo crops), plus per-state clips from a 14000px viewport, and once each at 1280×800 and 2560×1440. Every state is on the one page under a `.state` label, states 1–9 from round 4's brief and 10–13 from this one, in order. Written from what is built.

## What it is

Direction 1's band as the page, direction 4's lead at the top, at full width. Every action is one `.entry`; `.lead` and `.band` are the size property, and `.band.words` is the one thing this direction adds: a band whose review has words is 200px instead of 152px, holding three lines at 15px in a 62ch measure. The height is a class set from the data at render (`text != nil`); nothing on hover changes it.

Left to right on both sizes: the identity tile, the poster, the text block (sentence · title and year · review), the toolbar seat at the text block's foot; the time in its seat at the top right; the backdrop under the scrim to the right. Own rows: the tile filled with the button primary and a white initial, "You" set like any name.

## Every size, alpha and gap

**Frame.** Sidebar 52. `main` padding 24. `.content{max-width:none}` → 1820 wide at 1920. h1 22/600, 12 below. Tab strip: tabs 14px with 9px under, one hairline at 8% spanning the container, the house pill (36px) right-aligned 6px above the hairline; 14px from the strip to the first entry. Feed gap 6px, the lead included.

**Entry, both sizes.** Ground `oklch(13% 0.02 264)` (base-100); no border, no glass, no shadow — the picture's edge is the entry's edge. Radius 10 (band) / 12 (lead). Hover: every scrim alpha × .8 (`--s`) and the ground to 16%, both instant; the only transition on the page is the toolbar's 120ms opacity fade. Cursor: a 2px `--p` ring as a `::after` at inset 0 following the radius. All text over the entry carries `text-on-image`'s `0 1px 3px` black/85 shadow.

**Band.** Height **152**, or **200** with words. Padding 22 top and bottom. Tile 40 at x 18, y 56 (its centre at 76 = the poster's centre, on both heights). Poster 72×108 at x 74, y 22, base.css radius 6, shadow `0 3px 12px` black/55. Text block from x 164 to right −130, top 22, bottom 22 (so 108 tall on a 152 band, 156 on a 200). Line 1: 15/22 at 80%, the name 500 at 96%, the glyph 13px with a drop-shadow. Line 2: 18/24 semibold at 100%, 1px above, the year 13px at 60% with a 9px gap. Line 3: 15/22 at 80%, 6px above, `max-width: 62ch` (≈ 532px in Noto Sans; about 80 characters a line, 240 in three), clamped at three lines. Seat: 20px at the text block's foot — y 110–130 on a 152 band (the poster's foot line), y 158–178 on a 200 band. Time: 13/22 tabular at 72%, right 20, top 22 (line 1's height). Image box from x 560 to the right edge (1260 wide at 1920), left edge dissolved over 320px by a mask. Scrim, to the right, pixel stops: `.97 0 · .94 640 · .62 860 · .18 1100 · .06 1300`; plus a right-edge vignette `.48 → 0` over 220px under the time.

**Lead.** 1820×**340**. Padding 50. Tile 48 at x 32, y 61 (its centre on line 1's centre), the initial at 19px. Poster 160×240 (2:3 of 340 − 2×50) at x 100, radius 8, shadow `0 10px 28px` black/55. Text block from x 280 to right −160, 11px top padding. Line 1: 18/26. Line 2: 32/38 semibold, 2px above, gap 12, `text-on-image-lg`'s drop-shadow; the year 15px. Line 3: 16/24 at 80%, 10px above, 58ch (≈ 531px — the band's measure in pixels), clamped at three. Seat: y 270–290. Time: 13/26 at 72%, right 20, top 61. Backdrop full-bleed, no mask. Scrim, two layers in the base hue: to the right `.88 0 · .82 700 · .50 1040 · .14 1340 · 0 1620`; to the top `.35 → 0 at 40%` (136px).

**Tile.** Friend: the primary tint at 18% with a 1px inset ring at 22% and `0 2px 8px` black/35 (base.css's 15% vanishes on ink); the letter 600 in `--p`. Own: fill `oklch(62% 0.16 264)`, the initial `oklch(96% 0.008 264)` at 700, shadow black/40. Photo: a circular crop, ring white/18 inset. Own with a photo: a 2px ring in the own fill. The crop is a face centre and a zoom (`--cx --cy --z`), so the same numbers serve 40 and 48px.

**Toolbar.** Verbs 13px at 78% with 14px icons, padding 0 6, radius 6, hover fill 10% at 96%; on-states 96%; Ignore last with a 10px gap; plain states 66%; Downloading's 3px hairline at `--pct` (60% over 14%). Friend: List · Download · Ignore. Own: List · Download. No Delete.

**No artwork.** Ground `--glass-inset-bg`, scrim `.35 → 0` over 800px, the poster slot `.poster-empty` with a 1px white/6 edge, the same box height.

**Show older** 10px under the last entry at x 8. **Empty state** 26px down, 18px in: 17/24 semibold, 14/1.5 at 70% in 56ch, one ghost button.

Lowest read text: the year at 60%; plain states 66%; the time 72%.

## The crop, by the numbers

`object-fit: cover; object-position: 50% 30%` on every `.bd` in CSS; `.entry.repeat .bd` is `50% 38%`. The file has exactly those two values and no inline position. A 16:9 still scaled to the box's width; the visible window's top is `(1 − slice) × p`.

| Box at 1920 | Still scaled to | Slice | Window at 30% | Window at 38% |
|---|---|---|---|---|
| Lead 1820×340 | 1820×1024 | **33.2%** | 20.0–53.2% | — |
| Band 1260×152 | 1260×709 | **21.4%** | 23.6–45.0% | 29.9–51.3% |
| Band 1260×200 | 1260×709 | **28.2%** | 21.5–49.7% | 27.3–55.5% |

**What the 200px band does to the slice: 21% becomes 28%**, a third more of the still, most of it below the 152 band's window. On this page that is Hepburn from hairline to chin instead of brow to chin, both zombies' faces, Keaton's whole face. It is close to the 30% the measurement called safe for a capped box, and the words band gets it for free.

Sixteen rows, no failures at the fixed rule: eleven land on a face or a figure, five read as atmosphere (Metropolis's rings under the robot's head, Pioneer One's doorway, Nosferatu's eclipse with the face at the right edge, Carnival's figure, Sprite Fright's crowd). No hand-set positions; the mockup could not have rescued one if it wanted to.

**Rows 2–3 (state 12).** Row 2 is a 200 band at 30% (window 21.5–49.7%); row 3 a 152 band at 38% (29.9–51.3%). The second window is 93% inside the first: the offset moves the top edge down 8.4% of the still and the bottom edge 1.6%. It reads as two frames of one shot, not a repeat, but it is not the 30%-new-picture the rule gives a 152–152 pair (rows 6–7: 23.6–45.0 then 29.9–51.3, 28% new). The rule is obeyed to the letter; if it is amended, the offset should be measured on the window's bottom edge, not on `object-position`.

## Decisions

1. **One markup, a size property.** `.entry` renders both; `.lead` and `.band` set custom properties (`--h --pad --tile --tile-x --tile-y --pw --ph --px --bx --rad`) and the type sizes; `.band.words` sets `--h: 200px` and nothing else. The host sets `words` from the entry's text.
2. **Two heights, binary.** Words → 200; no words → 152. "Fine." (row 11) gets 200 with two empty lines. A length threshold was considered and rejected: it either needs a third layout (two lines at 14px on a 152 band for short reviews, as direction 1 had) or a rule that depends on the font's measure, and two reviews of similar length could land at different heights. Two layouts, one data property.
3. **The 200 band's top is the 152 band's top.** Padding 22, tile centred on the poster, poster at y 22, line 1 at y 22 on both; the extra 48px goes below: the third line's room and the seat. Every band's first line sits 22px under its top edge, so the left spine keeps its beat at each entry's start and the heights differ only at the end. Centring the poster or the text block on a 200 band was rejected: the spine would drift 24px on every words band.
4. **The words are set to be read.** 15px/22 at 80% (direction 1 had 14/20 at 78% and cut at two lines); 62ch. The one change to direction 1's scrim: the knee moves from 540 to 640 and the ramp with it (`.55@800 → .62@860`, `.16@1060 → .18@1100`, `.06@1260 → .06@1300`), so a line's tail at x≈700 sits on ≥.85 of ink — over the mask's first 140px the still contributes under 6% there. The mask stays 320. The clear picture starts about 60px later than in direction 1; the vignette is unchanged. The longest review in the data (row 13, 124 characters) fills two lines; the third is headroom before the clamp.
5. **The lead at 340.** Poster 160×240 (direction 4's 147×220 scaled to the taller box), tile 48 centred on line 1 (direction 4's seating; on a band the tile is centred on the poster because the poster *is* the band's height), the title at 32. The scrim is direction 4's two layers anchored in pixels for 1820: pass 1 was `.92 → .88 at 760` and the left 700px were a void, the mistake direction 4's REASONING records; `.88 → .82 at 700` lets the still through at ~15% under the text (Grant's face under the You · Charade lead in state 3).
6. **The lead has no border and no shadow.** Direction 4 gave it a glass border and `0 4px 16px`; the band has neither. One language: both are the image's edge on the page ground.
7. **The time as A.** Band: top-right at right 20, top 22, on line 1's height, over the vignette. Lead: right 20, top 61 — line 1's height on the lead. One x for the whole axis; 72% on both (direction 1 had 78% on the band, direction 4 60% on the lead).
8. **The tile is the author mark**, direction 1's ink adjustments kept. The own fill and the own-photo ring are one value, the button primary at 62% — the critique's item 6. "You" is 500 at 96%, like Cleo. The photo crop is a face centre and a zoom rather than pixel offsets so it scales with the tile: Ada `--z: 5.2 --cx: .53 --cy: .33` (the presenter, `one-step-beyond`), the own photo `--z: 3.5 --cx: .66 --cy: .37` (Sintel).
9. **Hover is one rule on both sizes.** `--s: .8` and the ground lift, instant. Direction 4's 120ms scrim transition on the lead is dropped: the ceiling is one element (the toolbar), not one duration.
10. **The lead's inset is its own.** Tile at x 32 against the band's 18; poster at 100 against 74; text at 280 against 164. The spine jogs 14px at the top of the page. Tried against the band's 18: a 48px tile 18px from the edge under 50px of top padding was cramped. The lead is the one dominant element; its margins are its size.
11. **Tried and rejected: a larger poster on the words band** (104×156, text from x 196). It fills the band and looks composed. It also moves the sentence's x on every other band, makes three poster sizes, and promotes reviews over listings — direction 4's ramp-by-position was praised for not doing that. The words band's growth is for the words.
12. **The no-artwork lead** is the same 340 box on the inset tone with a 160×240 empty slot. A different title from state 9 (Caligari against Coffee Run) so the two fallbacks do not read as one row repeated.
13. **State 10's second Everyone strip** is a window headed by Ada's review: rows 8, 9, 10, 11 — a review lead, then 200 · 152 · 200, the last being "Fine."
14. **The count is omitted at zero.**

## Requirements mapping

| Item | How it is met |
|---|---|
| Flat, newest first, one entry per action; size is position | Index 0 is `.lead`, every other index `.band`; no grouping, no re-sorting, no promotion by content beyond the height |
| One anatomy, one markup | `.entry` at two sizes; `.words` changes `--h` only |
| Identity tile: monogram, photo, own (button primary, white initial), own with a photo in a 2px ring; "You" neutral | States 1–3, 8; `.tile.you`, `.tile.photo`, `.tile.photo.you` |
| Crop rule: 50% 30% everywhere; 50% 38% on the second of two adjacent rows of one title; no per-title positions | CSS on `.bd` and `.repeat .bd`; `repeat` on rows 3 and 7 under Everyone and on row 3 in state 12; nowhere under Friends (row 7 and row 3 lose their neighbours) |
| Band scrim: direction 1's recipe; hover × .8 and a ground step; nothing else moves | `.band .scrim`, `--s`, `.entry:hover` |
| Lead scrim: direction 4's two layers in the base hue | `.lead .scrim` |
| Toolbar contract: fixed seat, height constant, friend List · Download · Ignore, own List · Download, no Delete | `.bar` at the body's foot; heights fixed per row at render |
| Scope pill, tab strip, entry rule, glyphs, empty state | As round 4; the pill on the strip's line at the right; Feed 16 · 11 · 5, omitted at zero; Friends 30 |
| 1 Everyone | `#f1`: the lead (Cleo · Sintel) and fifteen bands — 200/152/152/200/152/152/200/200/152/200/152/200/200/200/152 — then Show older |
| 2 Friends | `#f2`: rows 1, 3, 4, 5, 7, 8; the lead is still Cleo |
| 3 You | `#f3`: the lead is You · Charade with words; four bands; every tile filled |
| 4 You, empty | `#s4`: the headline, the body, one ghost action; no lead, no bands |
| 5 Friend's row hovered | `#f5`: the lead hovered — scrim × .8, ground lifted, List · Download · Ignore; `#f5b`: bands at both heights with Tracking · Download · Ignore, List · In library · Ignore, Listed · In library · Ignore |
| 6 Own row hovered | `#f6`: You · Charade (200) — Listed · In library; `#f6b`: You · Tears of Steel (200) — List · Downloading with the hairline |
| 7 Keyboard cursor | `#f7`: the ring on a band (radius 10) and on the lead (radius 12); the toolbar shown |
| 8 Friend with a photo | `#f8`: Sam's monogram, Ada's photo, the own tile with a photo in the primary ring |
| 9 No artwork, a band | `#f9`: Femi · Coffee Run on the inset tone, empty slot, 152 |
| 10 The lead as a review with words | `#f3` (You · Charade) and `#f10` (Ada · Night of the Living Dead leading rows 9–11 under Everyone) |
| 11 The lead with no artwork | `#f11`: Cleo · The Cabinet of Dr. Caligari, 340, inset tone, empty 160×240 slot |
| 12 Two adjacent bands of one title | `#f12`: rows 2–3, 200 at 30% then 152 at 38% |
| 13 A band hovered | `#f13`: Metropolis (152, seat at y 110) and Night of the Living Dead (200, seat at y 158), List · Download · Ignore |
| UIDR-012 eager images | Plain `<img>`, no `loading` |
| Text ≥ 55% | Lowest 60% (the year) |
| No JavaScript | None; `.hovered` and `.cursor` are static classes |

## The two heights: the column's rhythm and the time axis

Sixteen rows make a column of 3,094px: 340, then 8 × 200 and 7 × 152 with 6px between. The heights follow the data — 200/152/152/200/152/152/200/200/152/200/152/200/200/200/152 — so the column has a pulse instead of a metronome: a run of listings is a tight stack, a run of reviews a looser one. Because every band's first line is 22px under its top edge, the pulse is in the entries' ends, not their starts; the tile column reads as evenly seated even where the heights change. The first screen at 1920×1080 holds the lead and three bands and the top of a fourth (direction 1: six and a half bands; direction 4: the lead, three cards and a row). Every screen after holds about six bands.

The times keep one x (right 20) and lose their beat: successive times are 158 or 206px apart, and the lead's is 39px lower in its box than a band's. The axis is still a column at the right edge — the eye finds it — but it is no longer a ruler; the spacing says "review" or "listing" before the words do. That is the cost of the direction, and the honest one: the heights are information.

## Width, and what the Watchlist and Friends tabs do

Full width, Home's opt-out, as A. The lead spans 1820; the bands too. The strip and its hairline span the container; the pill sits at the far right. The Watchlist and Friends tabs keep their glass cards inside the same container; their grids gain columns at 1920 and lose them at 1280. The constants across the three tabs are the strip, the left edge and the h1.

## The time's seat

The far right, as A: the band's time at right 20 on line 1's height, over the .48 vignette; the lead's at the same x. It is 1,650px from the words on a band and the same on the lead. The argument for it here is the lead: a front page's dateline sits at the corner, and the band's time under the same x makes the corner a column. B's seat (the text zone's edge, about x 540, on line 1) would work on the words band too — line 1 is short, the 62ch measure is line 3's — and would put the time 24px from the sentence on every row. Rendered here at the far right so the owner sees A's seat against B's on identical rows; with B's seat the vignette goes and the picture's right edge is clear to the corner.

## A new arrival

The strip and the lead's box do not move: the new action becomes the lead in the same 340px. The old lead becomes the first band, at 152 or 200 by its words, and everything below moves down by 158 or 206px — the shipped list's one-row shift, but by an amount the reader cannot predict from the page. Nothing animates. A scope change re-projects from the newest action in scope: under You the lead is You · Charade, under Friends it is Cleo · Sintel. Show older appends bands; the lead is never paged.

## At 3 and at 300

Three: the lead and two bands, about 700px; three pictures under the strip, no Show older, nothing framing an absence. One: the lead alone.

Three hundred: 340 + 299 bands at 152 or 200 + 299 gaps — between 47,600 and 61,900px, about 55,000 at this data's ratio (eight of fifteen with words). What holds it is direction 1's spine (tile, poster, sentence at one x) and the changing pictures; what the heights add is the pulse. Backdrops are 300 eager loads at `?w=1280`; Show older pages the window to 16–32, so the number is the ceiling, not the page.

## 1280 and 2560

**1280×800** (content 1180). The lead's still is scaled to 1180 → a 51% slice: Sintel's face and the dragon, squarer, whole. The band's box is 620 wide → a 44% slice on a 152 band, 57% on a 200. The text zone, tile, poster and type are the 1920 numbers. The scrim's pixel stops mean the lead's clear zone (1340–1620 at 1920) is beyond the box, so the picture on the right sits under .30–.45 and is dimmer than at 1920; the band's picture likewise under .2–.5. Holds — the first screen is the lead, the Charade 200 band and the top of the next. The app's UI scale renders a 1280 panel at the 0.7 floor (≈ 1829 CSS px), so the 1× check is the edge case.

**2560×1440** (content 2460). The lead's slice is 25% (Sintel's eyes and nose, the mouth cut); the band's 14% at 152 and 19% at 200 — a letterbox; Hepburn's eyes and mouth on the 200 band, her eyes on the 152 at 38%. The text zone stays 640px of ink and the page is three-quarters picture; the time is 2,300px from the words. It holds as a wider cinema strip and gains no information. The UI scale renders a 2560 panel at ≈ 1920 CSS px, so this too is the 1× edge case.

## Standing rules: kept, bent, broken

| Rule | Status | Exception, precisely |
|---|---|---|
| UIDR-038 rule 2 — flat, newest first, one entry per action | Kept | Size is index 0 vs the rest; height is the row's own data. No grouping, no re-sort. |
| UIDR-038 rule 3 — one anatomy | Kept | One `.entry`; `.own` changes the tile's fill only; `.words` changes the height only. |
| UIDR-038 *hover jump* | Kept | 152, 200 and 340 at rest and hovered; the seat is in each box's fixed layout. |
| UIDR-038 *wall of watching* | Bent | The page is two-thirds picture. Exception: every entry leads with a sentence about a person in a fixed 640px text zone; the picture is the row's own title, after the words. |
| UIDR-038 *title-first row* | Bent (lead only) | The lead's title is 32px over an 18px sentence. Reading order is unchanged: tile, sentence, title. |
| UIDR-038 *social-network chrome* | Bent | The identity tile is a person device. Exception: it is the Friends tab's monogram, the photo slot is the owner's note; no handles, counts, reactions, links. |
| UIDR-038 *grouped rows*, *state as decoration*, *day dividers* | Kept | None; the only added colour is the heart, the own tile, the cursor. |
| UIDR-045 rule 3 — own = "You" in the primary | Replaced | The primary moves from the word to the tile (button primary at 62%, white initial). "You" is set like a name. |
| UIDR-045 rule 5 — one inset surface, hairlines | Broken | Entries 6px apart on the page ground, no container, no hairlines. A hairline between two pictures is a third picture. |
| UIDR-045 toolbar contract | Kept | Same slots, same states, a fixed seat per size; Ignore last; no Delete. |
| UIDR-033 — artwork when it is the subject | Kept | Each entry shows only its own title's backdrop and poster. |
| Colour is signal | Kept | Primary: own tile, cursor, tab underline; rose: love; no health palette. |
| MEASUREMENT's crop rule | Kept | Two values in CSS, none inline. |
| BRIEF-5 "the band's scrim is direction 1's recipe" | Bent | The knee at 640 instead of 540 and the ramp moved 40–60px right, so a 62ch third line sits on ≥.85. Shape, hue, alphas and the vignette unchanged. |
| BRIEF-5 "the lead's scrim is direction 4's recipe" | Bent | Direction 4's percentage stops (30 / 55 / 78%) became pixel stops for 1820 (700 / 1040 / 1340 / 1620) so the text zone is the same width at every viewport, direction 1's argument applied to the lead. Two layers, same hue. |
| "A 120ms opacity fade on the toolbar is the ceiling" | Kept | Direction 4's scrim transition on the lead is dropped. |
| `.mono` tint 15% | Bent | 18% with a 1px inset ring at 22% over ink, as direction 1. |
| `--p` for the own fill | Bent | The button primary (62% / 0.16) for the fill and the own-photo ring; `--p` stays the text primary. |
| Round 3's *no card per entry* | Bent | The entry is a per-row surface with no border, glass, shadow, padding box or chrome. |
| Text ≥ 55% | Kept | Year 60%, plain states 66%, time 72%, verbs 78%, sentence and review 80%. |

## Trade-offs

- **Most words bands are mostly air.** Six of the eight reviews on this page fit one line at 62ch; the 200 band then holds a line of text, two empty lines and the seat. At rest the empty lines are ink beside a bigger picture, and the render does not read as a hole; but the direction's 48px is headroom more often than it is words. Row 11 ("Fine.") is the extreme case, shown twice.
- **The offset rule under-delivers on a 200 → 152 pair.** Rows 2–3: 93% of the second window is inside the first. Numbers above.
- **Fewer actions per fold.** The lead and three bands on the first screen against direction 1's six and a half.
- **The time axis loses its beat.** Argued above; it is the direction's own cost.
- **The arrival shift is variable** (158 or 206px), where direction 4's ramp moved nothing above the list.
- **The spine jogs at the lead** (tile x 32 vs 18).
- **Bright stills fight the time** (Big Buck Bunny's sky, the Night of the Living Dead lead's speck at the corner); the .48 vignette and 72% hold it.
- **Bandwidth**: one backdrop per row, the lead's at full width; paged.

## With the others' settings

- **A's (all bands 152).** The column is a metronome, the time axis a ruler, two more bands per fold, and the words go back to two lines at 14px — the critique's "cut" reviews. This page's column would be 384px shorter.
- **B's (1280).** The 62ch measure runs to x 700 in a 1180 row whose image box starts at 560; the same scrim knee is needed. The 200 band's slice would be 49% (37% at 152) — the safest crop of any setting.
- **C's (900px box, right-aligned).** The words band's box is 900×200 → a 40% slice (30% at 152). The ink gap between the text zone and the picture's dissolved edge is where the words would go: a 62ch line ends at 700, the box begins at 920. C and words are the pairing I would render next if the owner likes the height rule but not A's 21%.

## The author mark at three friends and at thirty; the photo

As direction 1: own-versus-friend is the tile's fill, pre-attentive at any roster size; friend-versus-friend is the letter, then the name, and the photo once one exists. The tile is the photo's place at both sizes; the default is the monogram. The own tile with a photo keeps the mark as the ring.

## The one thing I am least sure of

The binary height rule. It is the cleanest rule (a data property, two layouts, no font in the decision) and it is what the brief asked for, but on this data it gives one-word and one-line reviews two empty lines each, and whether the owner reads that as room for the words or as air under them is the question this direction exists to answer. If it reads as air, the fix is not a threshold; it is C's setting with the words filling the ink gap, or A's two lines at 15px.
