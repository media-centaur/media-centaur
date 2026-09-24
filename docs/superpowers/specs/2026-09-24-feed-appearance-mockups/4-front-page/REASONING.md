# 4 · Front page — reasoning

Deliverable: `index.html` (links `../base.css`, art from `../art/`). Rendered with `page-shot` at 1920×1080 in the app frame, then at 1280×800 and 2560×1440; every state in the brief is on the one page under a `.state` label. Three full passes at 1920 plus two tail checks for states 8 and 9.

## Style

Hierarchy by recency. The newest action is the page's one dominant element: a 1280×300 card with the title's backdrop full-bleed under the house scrim, the poster at 147×220 over it, the sentence at 18px, the title at 32px semibold, the review text at 16px, the identity tile at 48px. The next three actions are backdrop cards in a row, 416×176 each. Everything after is the editorial list on the shipped inset surface, with the identity tile at 32px before a 64×96 poster. Newest first, flat, one entry per action; what changes down the page is size, not membership. One markup (`.entry`) renders all three tiers; `.lead`, `.card` and `.row` set sizes only. Colour is the artwork's own, the rose heart, and the primary for the own tile, the tab underline and the cursor ring.

## Every size, alpha and gap

**Frame.** Sidebar 52px; `main` padding 24px; `.content` max-width 1280px, left-aligned. Tab strip: tabs 14px on the strip's line, the house `.seg` pill (36px) right-aligned on the same line, 16px below it the lead.

**Lead (tier 1).** 1280×300, radius 14, glass border, shadow `0 4px 16px` at 25% black. Padding 40 / 36 / 40 / 32; gap 20. Tile 48px (initial 19px). Poster 147×220, radius 8, shadow `0 10px 28px` at 55% black. Body 220px tall with 11px top padding so the tile's centre sits on line 1's centre, 96px right padding to clear the time. Line 1: 18/26, 78% (name 500 at 96%), glyph 16px. Line 2: 32/38 semibold at 100%, year 15px at 62%, `.text-on-image-lg` drop-shadow. Line 3: 16/1.5 at 78%, three-line clamp, 58ch measure, 10px above. Time: 13/26 at 60%, top 40 right 36. Seat: 20px at the body's foot, 13px at 70%. Scrim, two layers: to the right `base` at .88 → .78 at 30% → .42 at 55% → .06 at 78% → 0; to the top `base` at .35 → 0 at 40%. `base` is `oklch(13% 0.02 264)`, the page ground, so the scrim fades into the page. Hover: the scrim at 86% of itself; the seat fades in.

**Cards (tier 2).** Three columns, `(1280 − 2×16) / 3` = 416px, 176px tall, gap 16, 16px below the lead. Radius 12, same border and shadow. Padding 16 / 18; gap 12. Tile 32px (initial 13px). Poster 64×96, radius 5, shadow `0 6px 16px` at 50%. Body 144px with 6px top padding. Line 1: 14/20 with 52px right padding for the time, glyph 12px. Line 2: 17/24 semibold, year 12px. Line 3: 13/1.45 at 78%, two-line clamp, 4px above. Time: 12/20 at 60%, top 16 right 18. Scrim: to the right .9 → .8 at 40% → .45 at 70% → .12; to the top .35 → 0 at 50%.

**List (tier 3).** One inset surface (`--glass-inset-bg`, radius 12), 16px below the cards. Row padding 14 / 18 / 14 / 16, gap 16, hairline at 8% between rows. Tile 32px; poster 64×96 (base.css `img.poster`); body min-height 96 with 5px top padding. Line 1: 15/22 at 72% (name 500 at 92%), glyph 13px. Line 2: 16/23 semibold, year 13px at 55%. Line 3: 14/1.5 at 70%, three-line clamp, 72ch measure, 4px above and below. Time: a 72px right column, 13/22 at 55%, tabular figures. Seat: 20px, spanning under the time column so Ignore sits on the time's edge (round 3's margins). Hover: a 6.5% fill on the row. The text column starts at 144px (16 + 32 + 16 + 64 + 16); "Show older" and the empty state align to it.

**Tile.** base.css `.mono` values: primary at 15% tint, the initial in primary, 600 weight. Own: primary fill, white initial. Photo: the image at `object-fit: cover` inside the circle. Own with a photo: a 2px primary ring (`box-shadow: 0 0 0 2px`).

**Cursor.** 2px primary ring, offset −1px, on the unit; it follows the lead's and the card's radius.

Lowest text alpha on the page: 55% (year, list time, scope labels). The seat's plain state is 60%.

## Decisions

1. **Size is a function of position, nothing else.** Index 0 of the sorted window is the lead, 1–3 are cards, 4 onward are rows. No title is merged, no author is grouped, no row is promoted for having words. Flat, with a ramp.
2. **The lead's title at 32px, not 28.** At 28 it read as a bigger list row inside a 300px band; at 32 it is the page's headline and the 18px sentence above it still reads first. Tried both against the render.
3. **The tile sits before the poster at every tier.** The brief places it there in the list; carrying that up the ramp means every unit's left edge reads the same way: who, what, words. Chat clients and Steam do the same. The tile's centre is on line 1's centre at every size (11 / 6 / 5px body padding), so it reads as that line's mark and not as a second column.
4. **The word "You" is set like any name.** The own mark is the filled primary tile; the word next to it is in the neutral at the name's weight. Two primaries 16px apart would say the same thing twice, and the tile is the channel that survives at 32px, which the word did not.
5. **The scrim is the house recipe at unit scale.** `.page-side-dim` is a left weight plus a bottom dim; the lead and the cards use the same two layers, in the page's base colour, tuned so the text's left half sits on ≥ .78 and the subject's right half is clear. The first pass was a step darker and the lead's left half was a black void; this is the step where the artwork shows through under the text without costing legibility.
6. **Cards carry line 3 at two lines.** The brief describes cards as sentence and title; a review's words are the action's content, and a card that says less than the row below it would invert the ramp. Two lines at 13px fit a 176px card with the seat at its foot.
7. **The poster is one size below the lead.** 64×96 on cards and rows, up from the shipped 56×84. The card's artwork is its backdrop, the row's is its poster; the same poster size keeps the two tiers related.
8. **The time is always at the right, on line 1's height.** Absolute top-right on the lead and cards, the right column on rows. Never inside line 1.
9. **Hover lightens, never lifts.** The scrim goes to 86% of itself on the lead and cards; the row takes the 6.5% fill. No height change anywhere; the seat is in flow at rest.
10. **The count is omitted at zero.** The You-empty state's tab reads "Feed".

## Requirements mapping

| Brief item | How it is met |
|---|---|
| State 1 Everyone, sixteen, then Show older | Lead (1), cards (2–4), rows (5–16), ghost "Show older" on the reading edge; Feed 16 |
| State 2 Friends, first six with own rows gone | Lead Cleo/Sintel, cards Nick/Charade, Nick/Metropolis, Bob/Pioneer One, rows Sam, Ada; Feed 11 |
| State 3 You, the five own rows | Lead You/Charade (a review, so line 3 is on the lead), cards Big Buck Bunny, Tears of Steel, The General, row Sprite Fright; Feed 5 |
| State 4 You, empty | The brief's headline, body and one ghost action, in the list surface on the reading edge; no lead, no cards |
| State 5 friend's row hovered | The lead hovered (scrim lighter, List · Download · Ignore seated) and a row at the 6.5% fill; "5 · continued" shows Listed (filled), In library, Tracking above List, Downloading with the 3px hairline, on cards and rows |
| State 6 own row hovered | A card and a row: Listed (filled) · In library; List · Downloading; no Ignore, no Delete |
| State 7 keyboard cursor | 2px primary ring, offset −1px, on a card (follows the radius) and on a row |
| State 8 friend with a photo | Nick's tile as a circular crop of `one-step-beyond-backdrop.jpg`, on a row and on a card; the own tile with a photo (`sintel-backdrop.jpg`) inside the 2px primary ring |
| State 9 no artwork yet | A row with `.poster-empty` at 64×96 and a lead with `.poster-empty` at 147×220 on the inset surface, same 300px box, text in the neutral ramp |
| Line 1: author medium, verb, glyph; second person | "You reviewed", "You want to watch"; friends "Cleo wants to watch"; the glyph inline, x-height sized (16 / 12 / 13px) |
| Line 2: title semibold + year | 32 / 17 / 16 semibold; year 15 / 12 / 13 |
| Line 3: review text, clamp named | 3 lines on the lead, 2 on cards, 3 on rows |
| Relative time in its own place | Top-right of the lead and cards; the 72px column on rows |
| Poster from `art/`, size named | 147×220 / 64×96 / 64×96 |
| Toolbar: fixed seat, height constant, slots | 20px seat at the body's foot in every tier, opacity 0 at rest; friend List · Download · Ignore last; own List · Download only |
| Whole-row click; names not links | `cursor: pointer` on the unit; names are spans |
| Scope: the house pill on the strip's line at the right; count follows scope | `.seg` right-aligned in `.tabs`; Feed 16 / 11 / 5 |
| Glyphs: filled heart in `--love`, thumbs, none | Round 3's sprite, unchanged |
| Identity tile: both states, own tile | Monogram default, photo state, own = primary fill with a white initial; own with a photo = the ring |
| Images eager (UIDR-012) | Plain `<img>`, no `loading` attribute |
| Text ≥ 55% | Year and time at 55%; nothing lower |
| No chips, badges, bars, avatars with photos we lack, per-row colour, day dividers, group headers, animation, light theme, real titles beyond `art/` | None; the only transitions are two 120ms opacity fades (see the rules) |

## The author mark at three friends and at thirty

At three, the tile carries the whole answer: Cleo, Nick and Bob are C, N and B, and the filled disc is You, before a word is read. The tile is also the Friends tab's device, so recognition carries across the two tabs.

At thirty, the tile still separates own from friend pre-attentively — a filled disc against tinted ones, at 48px on the lead, at 32 elsewhere — and the initial buckets the roster: a friend is "an S" before the name says which S. The name resolves the bucket; with thirty names the initials collide, and this direction does not add a hue per person to break the ties, because the house rule reads one hue per person as a chip palette (direction 2 exists to test that). The device that makes thirty tiles distinct is the photo: once friends publish one, the tile is unique the way it is on every feed the brief cites. Until then, at thirty, this page tells you from everyone at a glance and one friend from another by initial plus name.

## Where the photo goes and its default

The identity tile, at every tier, is the photo's place: a circular crop, `object-fit: cover`, at 48 / 32 / 32px. The default is the monogram. The own tile with a photo keeps the own mark as a 2px primary ring around the photo, so the fill's job survives the image. Nothing else on the page changes when a photo exists.

## The lead when the newest action is a bare listing

State 1 is exactly this case: Cleo wants to watch Sintel, no words. The lead shows line 1 and line 2 at the top of the body and the seat at its foot; the middle of the band is the backdrop. No synopsis, no "no review yet", nothing invented to fill it: a photograph with a headline is the front page's oldest form and the artwork is the row's subject. The lead's height does not depend on whether there are words, so a listing and a review make the same box.

## Show older, a new arrival, a scope change

- **Show older** appends rows to the list tier. The ramp is the first four of the window and paging never touches it.
- **A new action** re-projects the ramp in place: the new action is the lead, the old lead becomes card 1, card 3 becomes the list's first row. The lead and the card row are fixed-height boxes, so nothing above the list moves; the list gains one row at its top, which is the same one-row shift the shipped list produces today for a reader scrolled into it. Nothing animates.
- **A scope change** re-projects from the newest action in scope: under You the lead is You/Charade; under Friends it is Cleo/Sintel.

## At 3 rows and at 300

At 3: the lead and two cards; the third card slot stays empty rather than the two cards widening, so the third action fills the slot in place without moving the other two. At 2: the lead and one card. At 1: the lead alone, the whole page a single 300px band under the strip.

At 300: the ramp is 508px once (300 + 16 + 176 + 16), then 296 rows at 124px (a listing) to about 150px (a review), about 40,000px, on the shipped list surface with the tile column added. Nothing per-row accumulates beyond what the shipped list already carries; the time column is the axis.

## Standing rules: kept, bent, broken

Kept:

- **UIDR-038 rule 2, flat.** No re-sort, no grouping, no merge. The tier is the row's position in the sorted window and nothing else.
- **UIDR-033.** Every unit paints only its own title's poster and backdrop. No band of an unrelated title anywhere; the page ground is the app's radial.
- **UIDR-045's scope, entry rule, toolbar contract, modal.** The pill on the strip's line; the seat fixed and in flow; the same slots; withdrawing is the modal's.
- **UIDR-038 anti-patterns**: wall of watching (no watched rows, no poster grid), grouped rows (none), state as decoration (state appears only as the seat's words and the 3px hairline; scrims and glass are artwork treatment), hover jump (no height change), day dividers (none), social-network chrome (no handles, counts, reactions, photos we do not have; the tile is the Friends tab's own person device).
- **Colour is signal.** Primary: own tile, tab underline, cursor ring, the monogram tint the app already uses. Rose: the heart. Everything else is neutral or the artwork's own.
- **Text ≥ 55%**, images eager, no light theme, no icon fonts, no JavaScript.

Bent, each with its exception:

- **UIDR-045 rule 3** (own mark = the word "You" in the primary). Exception: the own mark moves from the word to the tile — primary fill, white initial, a primary ring when a photo replaces the fill — and the word "You" is set like any other name. The rule's intent, own rows told apart with no second component, holds: the tile is a property of the one row anatomy.
- **UIDR-038 title-first row.** Exception: on the lead only, the title is the largest type (32px) while the sentence above it is 18px. Reading order is unchanged — tile, sentence, then title — and the cards and rows keep the shipped 17/14 and 16/15 relation. The lead is the page's headline and a headline is the title.
- **"A 120ms opacity fade on the toolbar is the ceiling."** Exception: the lead's and cards' scrim lightening on hover is also a 120ms opacity transition, on the scrim layer, at the same duration. Set it to 0ms if the ceiling is read as one element, not one duration.
- **The shipped 56×84 poster.** Exception: 64×96 in the list and on cards, one step up, so the list tier is not the shipped row with a tile bolted on.

Broken: none.

## Page width, and the Watchlist and Friends tabs

1280px, left-aligned, the house content container. The lead spans it; the three cards divide it; the list fills it. Not full width, for two reasons: the list tier needs a measure and a right-hand time axis, and at 1820px the axis would sit 900px from the text; and a lead at 1820×300 is a 6:1 sliver, not a card. Home's full bleed is a hero with rails under it, not a list.

The Watchlist and Friends tabs keep their glass cards inside the same 1280. The tab strip with the pill is the constant on every tab; below it, the Feed's tiers and the other tabs' cards share left and right edges. The Friends tab's monogram is the same tile at 40px; the Feed draws it at 48 and 32.

## The 1280 and 2560 checks

**1280×800.** Content 1180: the lead 1180×300, the cards 382×176 — the brief's own numbers — the rows unchanged. The fold lands after the first list row: lead, three cards, one row. Line 3 on the You/Charade card wraps to two lines and the clamp holds.

**2560×1440.** In raw CSS pixels the 1280 column sits at the left, 52% of `main`, and the right half is the page ground, as on any container page. Under the app's screen-derived UI scale (2560 / 1920 = 1.33) the CSS viewport is 1920 wide and the page is the 1920 composition, so the raw check is the worst case, not the shipped one.

## Trade-offs

- **Two cards of one title show the same backdrop twice.** Rows 2 and 3 are both Charade, so cards 1 and 2 are the same image side by side, told apart by the tile (filled vs tinted) and the sentence. A different crop per row would be a lie about behaviour; the duplicate is what happens when two people react to one title in the same hour.
- **The focal point is hand-set.** Each backdrop's vertical crop (`--y` on the unit: 30–45%) was chosen by eye so faces sit in the band. The app has no focal-point data from TMDB; a fixed 40% is the fallback and will cut some faces on the 4.3:1 lead. This is the direction's largest unknown.
- **The list tier is plainer than the tiers above.** By design — the ramp — but from the fifth action on, the artwork is a 64×96 poster again.
- **At thirty without photos**, the friend mark is initial plus name; see above.
- **A lead with no artwork** is a 300px inset box with an empty poster and two lines. Honest and rare (backdrops warm with posters), and the fixed box is what keeps the page from jumping when the artwork arrives.
- **The right 540px at 1920 is the page ground.** The house container, at 70% of `main`; the lead's width is what makes the band read as a lead.
- **The lead clamps a review at three lines at 16px**, so a long review on the lead shows no more lines than it would in the list. The words are in the modal; the lead's job is the headline.
