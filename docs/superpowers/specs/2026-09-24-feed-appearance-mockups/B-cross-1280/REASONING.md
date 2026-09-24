# B · Cross, 1280 — reasoning

Deliverable: `index.html` (links `../base.css`, art from `../art/`). Rendered with `page-shot` at 1920×1080 in the app frame — three full passes, the first read as ten clips of an 8,000px tall capture, the later states re-shot from a scratch copy with the earlier sections hidden — then once each at 1280×800 and 2560×1440. Every state in the brief is on the one page under a `.state` label, in order: 1–9 from round 4, 10–13 from round 5. Written from what is built.

## Style

One visual language at two sizes inside the house container. The newest action in the scoped window is the **lead**: 1280×300, its title's backdrop full-bleed under direction 4's two-layer scrim, the poster at 147×220, the sentence at 18px, the title at 32px, the identity tile at 48px. Every other action is a **band**: 152px, its backdrop occupying the band from x = 560 to the right edge under direction 1's left-weighted scrim, the tile at 40, the poster at 72×108, the three lines in the dark zone. One markup — `.entry` with `.lead` or `.band` — and the size classes set dimensions only. Nothing frames either: no border, no glass, no shadow, no padding box; each entry's ground is the theme's base-100 (`oklch(13% 0.02 264)`), darker than the page's radial ground, so the dark half reads as a bar and the picture as the picture.

The identity tile is the author mark: a monogram for a friend, a photo when one exists, and for You a tile filled with the button primary carrying a white initial. "You" is set like any name. The time sits at the text zone's right edge on bands — x = 540, on line 1's height, the picture beginning at 560 — and at the top right on the lead. Colour is the artwork's own plus the rose heart and the primary (the own tile, the cursor ring, the tab underline, the pill's chosen option). System fonts, dark only, no JavaScript.

## Every size, alpha and gap

**Frame.** Sidebar 52; `main` padding 24; `.content` max-width 1280, left-aligned (x 76–1356 at 1920). Tab strip as shipped: tabs on the strip's line, the house `.seg` pill (36px) right-aligned on the same line, 16px below it the feed. Feed: a column, 6px gap.

**Shared.** Entry ground `oklch(13% 0.02 264)`; hovered `oklch(16% 0.02 264)` and every scrim alpha × .8 (`--k`), both instant. Cursor: a 2px `--p` ring drawn as the entry's top layer (`::after`, `inset: 0`, `border-radius: inherit`), because an outline on the entry paints under its positioned backdrop. Line 1: the name 500 at 96%, the rest at 80%, the glyph x-height sized, the heart in `--love`. Line 2: the title 600 at 100%, the year at 60%, 9px gap. Line 3: 78%. Time: 13px tabular at 62%. Text over the picture carries `0 1px 3px` black/.85 (UIDR-011); the lead's title takes the `drop-shadow(0 2px 10px)` of `.text-on-image-lg` instead. Toolbar: a 20px seat at the body's foot, opacity 0 → 1 in 120ms — the page's only transition; verbs 13px at 78% with 14px icons, 6px padding, 6px radius, a 10% fill and 96% on hover; `Listed` filled at 96%; Ignore last with a 10px gap; plain states (Tracking, In library, Downloading) at 66%; Downloading's 3px hairline at `--pct` (60% over 14%).

**Tile.** `--t` = 40 on a band, 48 on the lead; the initial at .4 × `--t` (16 / 19.2px), 600. Monogram: primary at 18% with a 1px ring of primary at 22% and a `0 2px 8px` black/.35 shadow (base.css's 15% tint vanishes on 13% ink). Own: `oklch(62% 0.16 264)` — the theme's button primary, not the 72% text primary — the initial `#fff` at 700. Photo: the image in the circle with a 1px ring of base-content at 18%. Own with a photo: a 2px ring of the same 62% fill. The photo stand-in is a window `--w` of the still's width centred on (`--x`, `--y`) of the frame, sized from `--t` so one crop serves both tile sizes: One Step Beyond's presenter at .24 / .53 / .37; Sintel at .30 / .66 / .37.

**Band.** 152 tall, radius 10. Picture box from x = 560 to the band's edge (720 wide at 1280), `object-fit: cover; object-position: 50% 30%`, its left edge dissolved over 160px by a mask. Scrim, to the right, base hue at .97 @ 0, .94 @ 540px, .50 @ 680, .16 @ 820, .05 @ 980, .02 @ 1280 — pixel stops, so the text zone is identical at every band width; no right-edge vignette, since the time is not there. `.in` is 540 wide with padding 22 0 0 20 and gap 16: tile x 20–60, poster x 76–148 (72×108, radius 6, `0 3px 12px` black/.55), body x 164–540 (376px). Body 121 tall with 9px top padding, so the 40px tile's centre sits on line 1's centre and the tile's top on the poster's top: line 1 15/22 (y 31–53, 56px right padding), line 2 18/24 (53–77), line 3 14/19 clamped at two lines (81–119, 4px above), the seat 123–143 — 4px under a two-line review, its centre 3px under the poster's foot line at 130, 9px above the band's edge. Time at top 31, its right edge at x = 540.

**Lead.** 1280×300, radius 14. Picture full-bleed, the same crop rule. Scrim, two layers: to the right, base at .88 @ 0% → .78 @ 30% → .42 @ 55% → .06 @ 78% → 0; to the top, .35 → 0 at 40%. `.in` fills the box with padding 40 36 40 32 and gap 20: tile x 32–80, poster x 100–247 (147×220, radius 8, `0 10px 28px` black/.55), body x 267–1148 (96px right padding clears the time). Body 220 tall with 11px top padding (the 48px tile's centre on line 1's centre): line 1 18/26 (y 51–77), glyph 16px; line 2 32/38, year 15px (79–117); line 3 16/24 clamped at three lines, 58ch, 10px above (127–199); the seat 240–260. Time at top 51 (line 1's height), right 36.

**No artwork.** Ground `--glass-inset-bg`; the band keeps a .35 → 0 scrim over its first 800px, the lead has none; the poster slot `.poster-empty` at the size with a 1px white/.06 edge; no text shadow; hover lifts to `oklch(22% 0.017 264/.5)`.

**Show older** on the tile's edge (x = 20). **You, empty**: the copy on the ground at the tile's edge — 17/24 headline, 14/1.5 body at 70% on a 56ch measure, one ghost action.

Lowest read text: the year at 60%; the time at 62%; plain states at 66%. Separators and icons only below that.

## The slice: what 720px gains

At 1280 the band's picture box is 720×152: the still scales to 720×405 and the band shows **37.5%** of its height, the window running from 19% to 56% of the frame at `50% 30%` (24%–61% at 38%). Direction 1's 1260px box showed 21%, needed thirteen hand-set positions, and still called Nosferatu a colour field. Here, with one rule and no hand: Keaton's whole face, Hepburn's and Grant's, the Metropolis robot from crown to chest, both figures in Tears of Steel, all four Sprite Fright faces (direction 1 set that one at 58%), Nosferatu's eye beside the eclipse, the Carnival of Souls woman, the two zombies. Cosmos Laundromat is the marginal case — the sheep's eyes sit at the window's top edge — and Pioneer One is atmosphere at any position. Sixteen of sixteen land a subject or read as atmosphere; none reads wrong. That is the lever MEASUREMENT.md measured, seen on the real rows: a fixed position is only safe when the slice is tall enough, and the 1280 container makes it tall enough.

The lead shows 42% (1280×720 scaled, the window 17.5%–59%); every lead on the page lands its subject.

## Decisions

1. **Size is position.** Index 0 of the scoped window is the lead; everything else is a band. Nothing is promoted for words, no title merged, no author grouped. Two sizes, not three.
2. **One markup.** `.entry > .bd + .scrim + .in(.tile, .poster, .body(.l1, .l2, .l3, .bar)) + .when` renders both; `.lead` and `.band` set only heights, paddings, gaps, type sizes and the time's seat. `.own` changes the tile's fill and nothing else.
3. **The tile's top on the poster's top, its centre on line 1's centre, at both sizes.** The body's top padding (9 / 11) does this. The tile is the sentence's mark and the sentence begins with the name. I tried the alternative — the band's tile centred on the band's height, as direction 1 seated it (`margin-top: 34px`, rendered as a scratch comparison) — and it is calmer on a lone band, but it makes two placement rules for one anatomy, and it moves the tile off the line whose first word it stands for. Not taken.
4. **"You" neutral.** The filled tile is the own mark; the word beside it is set at the name's weight and alpha. Two primaries 16px apart would say one thing twice, and the tile is the channel that survives at 40px.
5. **The own fill is the button primary.** `oklch(62% 0.16 264)` with a white initial has contrast a 72% fill does not; `--p` (72%) stays the text and interaction primary. The own photo's ring uses the same 62%, so the own mark is one value in both tile states.
6. **The band's picture begins at 560, not at 0.** Inherited from direction 1 and the reason the slice is 37%: under a .97 scrim the first 540px of a still contribute a colour cast and nothing else, and a box that starts where the words end is scaled to a shorter width. The mask dissolves the box's edge over 160px (direction 1 used 320 over a box nearly twice as wide); the first render used 200 and the dissolve ate a third of the picture — Grant's face sat dimmed in it — so the mask and the scrim's fall both tightened.
7. **No right-edge vignette.** Direction 1's `to left` .48 → 0 gradient existed to seat the time over the picture. With the time at 540 the picture's right 220px is clear to the band's edge. This is the seat's first tangible gain.
8. **The lead's scrim is direction 4's recipe, un-retuned.** The brief fixes it; I rendered the hardest case (Cosmos Laundromat, a light grey still on the left, state 8) and the 16px review holds on the .78 plateau with the shadow. Hover multiplies its alphas by .8 like the band's, through the same `--k`, and the step is instant — direction 4 transitioned the scrim over 120ms, which this page does not: the fade is the toolbar's alone.
9. **The lead has no border and no shadow.** Direction 4 gave the lead a glass border; the band has none ("a hairline between two pictures is a third picture"). One language means one edge rule: the image's edge, the ink the text needs.
10. **The lead's time on line 1's height.** Direction 4 seated it at the padding's top (40); here it is at 51, the same line as the sentence, matching the band's rule.
11. **The seat straddles the poster's foot.** Direction 1 put the seat's bottom on the foot line and its two-line review overlapped the seat by 4px. Here the body is 121 tall, the seat 123–143, the poster's foot at 130, and a two-line review ends 4px above the seat. The first build had the body at 117 with the seat starting where the review's box ended; hovered, the toolbar sat at the paragraph's line pitch and read as a third line of the review (the verbs and the review are both at 78%). Four pixels and the icons make it a toolbar again (state 13 shows it hovered).
12. **Two lines of review at 376px.** The body ends where the time and the picture begin. The General's review is cut with an ellipsis at two lines; the words are in the modal. Direction D's setting would grow that band; see below.
13. **The photo tile at one crop for two sizes.** The window fraction and centre are per photo, the pixels derive from `--t`, so the lead's 48px tile and the band's 40px tile show the same face. A published photo would be a portrait already; the mockup stands one in with a windowed still, which BRIEF.md permits for this state only.
14. **The crop rule, to the letter.** One `object-position: 50% 30%` on `.bd`; `.bd.off` at `50% 38%` on the second of two adjacent rows of one title. No inline positions anywhere (grep: zero). The adjacency is computed over consecutive rows in the strip regardless of size, so a band following a lead of the same title would take the offset too.
15. **The count is omitted at zero.** The You-empty strip's tab reads "Feed".

## Requirements mapping

| State / item | How it is met |
|---|---|
| 1 Everyone | Lead Cleo · Sintel; fifteen bands; rows 3 and 7 at 38% (Charade after Charade, Big Buck Bunny after Big Buck Bunny); ghost "Show older" on the tile's edge; Feed 16 |
| 2 Friends | Lead Cleo · Sintel; bands Nick · Charade (30% — no adjacent duplicate once row 2 is gone), Nick · Metropolis, Bob · Pioneer One, Sam · Big Buck Bunny, Ada · Night of the Living Dead; Feed 11 |
| 3 You | Lead You · Charade — a review, its words at 16px on the lead — then Big Buck Bunny, Tears of Steel, The General, Sprite Fright, every tile filled; Feed 5 |
| 4 You, empty | The brief's headline, body and one ghost action on the ground at the tile's edge; no count |
| 5 friend hovered | The lead (Cleo · Sintel) and a band (Nick · Metropolis) with `.hovered`: List · Download · Ignore seated, the scrim at .8, the ground lifted; "5 · continued": Tracking above List, In library, Listed (filled), each with Ignore last |
| 6 own hovered | You · Charade: Listed (filled) · In library; You · Tears of Steel: List · Downloading with the hairline; no Ignore, no Delete |
| 7 cursor | The 2px ring on a band (radius 10) and on the lead (radius 14); toolbar shown |
| 8 photo | Nick's photo at 48 on the lead; Sam's monogram, Ada's photo at 40, and You with a photo inside the 2px 62% ring, on bands |
| 9 no artwork | Femi · Coffee Run as a band: inset tone, empty poster slot, no picture |
| 10 lead = review | A second Everyone strip, rows 8–11: Ada · Night of the Living Dead leads with a two-line review; the You scope's lead (3) is the other case |
| 11 lead, no artwork | Cleo · Coffee Run as the lead: the same 300px box on the inset tone, the 147×220 slot empty, no scrim |
| 12 adjacent duplicates | Rows 2–3 as two bands: the first at 30%, the second at 38%; Hepburn's eyes sit ~18px higher on the second |
| 13 band hovered | Ada · Night of the Living Dead at rest, then `.hovered`: the scrim step on a bright still, the seat under a two-line review |
| Line 1 / 2 / 3 anatomy; second person on own rows | As inherited; "You reviewed", "You want to watch"; the glyph in the run |
| Time in its own place, never in line 1 | `.when` is a sibling of the body: x = 540 on bands, top right on the lead |
| Poster from `art/`, size named | 72×108 / 147×220 |
| Toolbar contract | One 20px seat in flow at rest; the row's height constant; friend List · Download · Ignore, own List · Download; no Delete |
| Whole-row click; names not links | `cursor: pointer` on the entry; names are spans |
| Scope pill; count follows scope | `.seg` on the strip's line at the right; 16 / 11 / 5 / none |
| Glyphs | Round 3's sprite verbatim; 13px on bands, 16px on the lead |
| Data | The sixteen rows, times, texts and title states verbatim; Friends 30; Charade, Big Buck Bunny, Pioneer One, Spring, Tears of Steel and Sprite Fright consistent across their rows |
| UIDR-012 eager | Plain `<img>`, no `loading` attribute |
| Forbidden list | No chips, badges, bars, avatars with photos we lack (the photo state is the brief's permitted stand-in), per-row colour, day dividers, group headers, entrance animation, light theme, titles beyond `art/`, text below 55%, hover height change; no JavaScript at all |

## The time seat, argued

The brief seats it at x = 540: right-aligned on line 1, the picture beginning 20px to its right. Against direction 1's far right:

- **Distance.** At 1280 the far right is ~1,200px from the words (1,700 at full width); at 540 the time is 150–350px from the sentence's end, inside the zone the eye is already reading. Reading down the column, the times form a second column at one x on every band — a time axis a reader meets while scanning the words, which the far-right seat never gave.
- **The picture.** At the far right the time sat over the still under a .48 vignette; every band paid 220px of its picture for a four-character word. At 540 the time is on ink at .94 and the picture's right edge is clear to the band's edge.
- **One rule with two results.** The rule is "right-aligned on line 1 at the body's right edge". On a band the body ends where the picture begins (540); on the lead the body ends at the padding (1244), so the lead's time is at its top right, as direction 4 and direction A have it. Visually those are two seats; structurally they are one. The lead has no boundary between words and picture, so it has no text-zone edge to sit on.
- **The cost.** On a listing with a short line 1 the time floats in ink — "Nick wants to watch" ends at ~x = 330 and the time begins at ~490 — anchored only by the other times in the column; on a lone band (states 9, 13) it looks less seated than it does in a column. And the review's ragged right and the time share one x, so a long review ends where the time column runs. I would still not move it back: the axis is the thing a feed needs and the far right made it an orientation, not a read.

## A new arrival

The new action becomes the lead; the old lead becomes the first band — the same entry with its size property flipped; every band below shifts down by 158px (152 + 6). For a reader at the top, the hero swaps and one band appears under it. For a reader scrolled into the column, the rows shift by one band, which is what the shipped list does today when a row arrives. Nothing animates and no box changes height in place. Direction 4 could claim that nothing above its list moved; this page has one tier below the lead, so the shift is simpler and the same as the shipped list's.

A scope change re-projects from the newest action in scope (Cleo · Sintel under Everyone and Friends, You · Charade under You). Show older appends bands; the lead is never touched by paging.

## At 3 and at 300

At three: the lead and two bands, 616px under the strip, no Show older. At one: the lead alone. Three pictures on a dark page is a composition; nothing frames an absence.

At three hundred: 300 + 299 × 158 ≈ 47,500px, paged by Show older into windows of 16–32. What holds it is the fixed spine — tile at x = 20, poster at 76, sentence at 164, time at 540 on every band — and the picture changing on every band. Adjacent rows of one title show the same still twice; the 8% offset stops the two frames from being pixel-identical and does no more than that. Three hundred eager backdrops at `?w=1280` is ~45MB across the whole history and ~2.4MB per window; the host resolves them like posters.

## Width; Watchlist and Friends

1280px, left-aligned — the container every other container page draws, with `main`'s 24px padding to its left. Not full width: that is direction A's setting, rendered so the owner sees the two side by side. What the container buys is the slice (37% against 21%); what it costs is 540px of ground to the right of every band at 1920.

The Watchlist and Friends tabs keep their glass cards inside the same 1280; the strip and its pill are the constant across the three tabs; the Friends tab's monogram is this tile at 40.

## 1280×800 and 2560×1440

**1280×800.** Content 1180. The lead is 1180×300 (the still at 1180×664, a 45% slice, the face whole). The band's box is 620px (x 560–1180): the still at 620×349, a 44% slice — squarer, whole faces, the dissolve a larger share of a smaller picture. The text zone, the time's x and every size are identical to 1920; the pill fits the strip. The fold shows the lead, two bands and a third's top. Holds.

**2560×1440, raw.** The column sits in the left 1280 of a 2,484px `main`; the right half is page ground; the fold shows the lead and six bands. Under the app's screen-derived UI scale (2560 / 1920 = 1.33) the CSS viewport is 1920 wide and this is the 1920 composition, so the raw check is the worst case, not the shipped one. It holds as a column; it does not fill the monitor, and no container page does.

## Standing rules: kept, bent, broken

| Rule | Status | The exception, precisely |
|---|---|---|
| UIDR-038 rule 2 — flat, newest first, one entry per action | Kept | The lead is index 0; no grouping, no merge, no re-sort. |
| UIDR-038 rule 3 — one anatomy | Kept | One markup; `.own` changes the tile's fill only. |
| UIDR-038 *wall of watching* | Bent | The page is a column of stills at 1920. Each entry leads with a person's sentence in a fixed 540px text zone; the still is the row's own title, after the words. |
| UIDR-038 *title-first row* | Bent, lead only | The lead's title is 32px under an 18px sentence; reading order (tile, sentence, title) is unchanged and bands keep 15/18. |
| UIDR-038 *grouped rows*, *day dividers* | Kept | None. |
| UIDR-038 *state as decoration* | Kept | Colour on the page is the artwork's, the heart, the own tile and the cursor. |
| UIDR-038 *social-network chrome* | Bent | The identity tile is the Friends tab's monogram (`Discovery.PersonCard`), the app's existing drawing of a person; the photo slot is the owner's note; no handles, counts, reactions, links. |
| UIDR-038 *hover jump* | Kept | 152 / 300 at rest and hovered; the seat is in the fixed layout. |
| UIDR-045 rule 3 — own = "You" in the primary | Replaced | The primary moves from the word to the tile: a 62% fill with a white initial (a 2px ring when a photo fills it); "You" set like a name. |
| UIDR-045 rule 5 — one inset surface, hairlines | Broken | Entries 6px apart on the page ground, no container, no hairlines. |
| UIDR-045 toolbar contract | Kept | Same slots, states, seat idiom; Ignore last; no Delete. |
| UIDR-033 — artwork when it is the subject | Kept | Each entry shows only its own title's backdrop and poster. |
| UIDR-012 eager images | Kept | No lazy loading. |
| Colour is signal | Kept | Primary for the own tile and interaction; rose for love; no health palette. |
| The 120ms opacity ceiling | Kept | The toolbar's fade is the only transition; the scrim step is instant. |
| Text ≥ 55% | Kept | Year 60%, time 62%, plain states 66%. |
| The crop rule (MEASUREMENT.md) | Kept | `50% 30%` everywhere; `50% 38%` on the second adjacent row of one title; no per-title values. |
| Round 3's *no card per entry* | Bent | Each entry is a surface again, carrying no border, glass, shadow or padding box. |
| `.mono` tint at 15% | Bent | 18% with a 1px ring at 22% over 13% ink. |
| `--p` for the own fill | Bent | The button primary (62% / 0.16) so a white initial has contrast. |
| BRIEF's "backdrop filling the band" | Bent | The band's box begins at 560 (decision 6); the lead's fills the box. |
| Direction 4's lead border, shadow and time seat | Dropped / moved | No border or shadow on the lead (decision 9); the time on line 1's height (decision 10). |

## What I would change with the other settings

- **A, full width.** The band's box would be 1260 and the slice 21%; I would keep the time at 540 rather than the far right — once the time is on the text's side, the picture's width is irrelevant to it — and drop the vignette there too. The lead at 1820×340 is a different object; this page's lead is a card, A's is a strip.
- **C, capped at 900.** At 1280 there is no ink gap to judge: the box starts at 560 and the time at 540. C's question — composed or a hole — is one this width never asks.
- **D, words.** The two-line clamp at 376px cuts The General's review; a 200px band with three lines at 15px would hold it. The cost D pays in rhythm (two band heights) this page does not; the cost this page pays is the ellipsis.

## Trade-offs

- **540px of ground** to the right of every band at 1920, and 1,200 at 2560 raw. The container's presence is the lead's; the bands are pictures 720px wide, ~460 of them clear once the dissolve and the scrim's fall are spent.
- **Adjacent duplicates** are still two of one still. The offset is 20px of a 405px scaled image; it stops an exact repeat and nothing more.
- **The lead's scrim has one weak case** — a light still on its left third (Cosmos Laundromat) — and the brief fixes the recipe. It holds with the shadow; it is the least comfortable text on the page.
- **A long review is cut at two lines** on a band. The modal has the rest.
- **The time floats on a listing band** (see the seat, argued).
- **Cosmos Laundromat at 30%** cuts the sheep's crown; the eyes are in. The fixed rule's marginal case on this set.
- **The own photo's ring** is the fill's 62%, one step quieter than the 72% cursor ring; on a bright photo it is a thinner mark than the filled tile.
- **Eager backdrops** cost ~150KB a band; a page of sixteen is ~2.4MB, on a LAN desktop app that already trades bandwidth for perception.

## The one thing I am least sure of

Whether the band at 1280 has the presence the owner asked for. The slice is safer and every still lands, but each band is 40% ink and 60% picture of which about two-thirds is clear, and the monitor's right 540px is ground. Direction 1 popped because the picture ran to the edge; this page pops on the lead and is handsome below it. Whether handsome is enough is the question this direction exists to put beside A, and I cannot answer it from the mockup — only the two renders side by side can.
