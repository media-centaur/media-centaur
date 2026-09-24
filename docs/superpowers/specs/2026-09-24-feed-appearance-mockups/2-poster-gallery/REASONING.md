# 2 · Poster gallery — reasoning

Deliverable: `index.html` (links `../base.css`, artwork from `../art/`). Rendered with `page-shot` at 1920×1080 (four passes), then once at 1280×800 and 2560×1440; every state in the brief is on the one page under a `.state` label, in order. No JavaScript.

## Style

The Feed takes the full width of `main` (Home's opt-out, `.content{max-width:none}`) as a lattice of glass cards: three across at 1920, two at 1280, four at 2560. Every card is the same height — 208px — because the text block is sized to the poster and the review text is clamped inside it, so the lattice is level from the first row to the last.

A card leads with its title's poster at 120×180 on the left, with a real drop shadow so it sits on the glass. The text block beside it is anchored at two corners: the author's name, top left, at 16px semibold in that friend's own hue (You in the primary); the relative time, bottom right, at 13px. Between them: the verb and the sentiment glyph on the name's line, the title at 18px semibold with the year, the review text at 15px clamped at four lines. The toolbar's seat is the card's foot — the same 20px line the time sits on — empty at rest and faded in on hover, with Ignore pushed against the time's edge.

Colour: the rose heart, the primary for the tab underline, the pill's chosen option, the cursor ring and You; and, new to this direction, one pastel hue per friend on the name text alone. Everything else is the neutral ramp, the glass tokens and the artwork's own colour.

## Decisions

1. **Full width, and a lattice rather than a column.** The diagnosis's fifth point is that the shipped page composes in 47% of the screen. A card lattice is the one structure that fills 1920 without stretching a row across it: the column count follows the width (`repeat(auto-fill, minmax(560px, 1fr))`), and the text block stays 418–439px wide at every size, so the review measure is 52–55 characters whether there are two columns or four.
2. **The poster stays at 120×180.** I tried the composition at 128×192 on paper: the card grows to 220 and the row pitch to 236, which pushes the fourth row below the 1080 fold. At 120×180 the frame holds four full rows (twelve cards, against the shipped page's eight rows) with the fifth row's top edge showing under the fold as the scroll cue.
3. **Every card is 208px.** The body has `min-height` equal to the poster and the review is clamped at four lines of 15px (90px); the tallest possible text block (22 + 2 + 25 + 6 + 90 + 20 = 165px) is shorter than the poster, so no card is ever taller than another. The lattice never goes ragged, the times across a row share a baseline, and the toolbar's seat is at the same y in every card of a row.
4. **The time moved to the foot.** Pass 1 had it at the top right of the text block, the editorial list's column translated into the card; the result was a card anchored at one corner with three-quarters of a listing's text block empty below it. At the foot's right corner it becomes the second anchor: name top left, time bottom right, and the empty middle of a listing card reads as air between two fixed points rather than as missing content. It is still in its own place, never in line 1.
5. **The toolbar and the time share the foot.** The seat is the foot's left part (`.bar`, flex 1), the time its right end, 14px apart. Ignore keeps the inherited `margin-left: auto`, so on hover it lands against the time — on the time's edge, as in round 3 — isolated from List and Download by the whole width of the seat. The time is always visible; only the seat fades.
6. **The friend mark is the name's hue and nothing else.** `oklch(78% 0.10 h)`, hue per friend, applied to the 16px semibold name. Not to the verb, not to the border, not to a fill, not to an icon. The verb stays at the neutral 72% so the sentence reads as a sentence with a coloured subject.
7. **The own mark is You in the primary, plus the card's primary border.** The name alone is a hue change on a short word — the diagnosis's second point — so the own card also takes the You card's own precedent, `.own-border`, raised from 30% to 40% alpha because 30% did not register on the glass at 1920 (checked in pass 1). That is a shape channel (the card's outline) on top of the colour channel, with no fill and no bar. Own cards are otherwise identical to friends'.
8. **No identity tile at rest.** The direction's answer to the tile question is that the name is the mark; a 24px photo circle appears before the name only when a photo exists, and when there is none the line starts with the name. A monogram on every card would put 16 primary-tinted circles on a page whose own mark is the primary, and would repeat the hue the name already carries.
9. **Hover is a fill step, not a lift.** Glass background from `oklch(20% 0.02 264/.45)` to `oklch(24% 0.02 264/.55)`, border from 9% to 14%, no transform, no shadow change; the only transition is the seat's 120ms opacity fade.
10. **The title is the confident line.** 18px semibold in `--bc`, the largest and brightest text on the card; the name is one step smaller and carries the colour instead. The eye lands on the coloured name first (it is first, and it is the only hue on the card), then the white title — author, action, title, in that order.
11. **Show older on the reading edge.** A ghost button under the lattice's first column, its text aligned to the first card's left edge (−6px for the button's own padding).
12. **The empty state is plain text on the ground**, not an empty card: a card with no poster would read as a broken row on this page.

## Requirements mapping

| Brief item | How it is met |
|---|---|
| State 1 · Everyone, sixteen, then Show older | The lattice in the brief's order, 1–16, own cards at 2, 6, 9, 13, 16; Feed 16 · Friends 30; ghost "Show older" below |
| State 2 · Friends, the first six with own rows gone | Rows 1, 3, 4, 5, 7, 8; Feed 11 |
| State 3 · You, the five own rows | Rows 2, 6, 9, 13, 16; Feed 5 |
| State 4 · You, empty | The brief's headline (16px 600) and body (14px at 70%, 56ch), one ghost action "Settings → Social"; the count omitted at zero |
| State 5 · A friend's card hovered | Three cards: List · Download · Ignore; Tracking · Download · Ignore; List · In library · Ignore |
| State 6 · An own card hovered | Two cards: Listed (filled) · In library; List · Downloading with the 3px hairline — no Ignore, no Delete |
| State 7 · The keyboard cursor | `outline: 2px solid var(--p); outline-offset: -1px`, following the card's 14px radius; the seat shown |
| State 8 · A friend with a photo | Ada's card with a 24px circular crop of `sintel-backdrop.jpg` before the name; Femi's card beside it shows the default (no tile) |
| State 9 · No artwork yet | `.poster-empty` at 120×180 (10% alpha) in the poster's place; nothing else changes |
| Line 1: author (medium), verb, glyph | Name 16px 600 in the hue (the direction raises the weight one step), verb 15px at 72%, glyph 13px `vertical-align: middle` in the text run |
| Own rows in the second person | "You reviewed", "You want to watch" |
| Line 2: title semibold + year | 18px 600 in `--bc`, year 13px at 55%, nowrap with ellipsis |
| Line 3: review text, clamped | 15px/1.5 at 70%, `-webkit-line-clamp: 4` |
| The time in its own place | The foot's right end, 13px at 55%, tabular figures |
| Poster: real artwork | `img.poster` 120×180 from `art/<slug>-poster.jpg`, 6px radius, 1px 8% border, shadow `0 8px 20px oklch(0% 0 0/.55)`, eager |
| Toolbar: fixed seat, shown on hover/cursor, height constant | The 20px foot line is in flow at rest; `.bar` opacity 0 → 1 in 120ms; the card is 208px in every state |
| Friend's row: List · Download · Ignore last; Listed filled; Tracking above List; Downloading hairline; In library | All present across states 1, 5 |
| Own row: List · Download only | States 3 and 6: Listed/List · In library/Download/Downloading, no third slot |
| Whole-row click; names not links | `cursor: pointer` on the card; names are plain spans |
| Scope: the house pill, on the strip's line at the right | `.seg` with `margin-left: auto` in `.tabs`; counts 16 / 11 / 5 |
| Glyphs: inline SVG symbols | The round-3 sprite, unchanged |
| Photo state: circular crop of a backdrop | `object-fit: cover; object-position: 62% 30%` |
| Frame: sidebar, main, content | `base.css`'s shell; `.content{max-width:none}` |
| Text alpha floor 55% | Lowest read text is 55% (time, year, state keys); plain toolbar states 60% |
| No chips, badges, bars, day dividers, group headers, animation beyond the fade, light theme, icon fonts, external assets, JS | None present |

## The author mark at three friends and at thirty

The hue is derived from the public key: `hue = 290 + (first two bytes of the key, big-endian) mod 310`. That maps the key onto every hue except the 50° band 240–290 around the primary (264), so no friend can land in You's blue. Lightness and chroma are fixed at 78% and 0.10; only the hue varies, so every name has the same weight on the page and none is louder than another. The mockup's six: Cleo 40, Nick 195, Bob 95, Sam 310, Ada 150, Femi 0.

At three friends the marks are three well-separated pastels and the page is legible by colour alone: a reader learns "Nick is teal" in one visit and finds Nick's cards without reading. At six (the window shown) they still separate; the nearest pair is Sam and Femi at 50°.

At thirty, honestly: thirty keys land on 310° of hue, about 10° apart on average and clustered by chance, so two friends will share a hue neighbourhood and the hue does not uniquely name a person. What it still does at thirty: (1) the own mark stays unique, because the primary's band is skipped and no friend's name is at the primary's chroma; (2) in any one window of sixteen cards only a handful of authors appear, and those are usually distinguishable; (3) a friend's hue is stable across visits, so the friends a reader follows most become recognisable even if the roster as a whole is not. The name text remains the identifier; the hue is the pre-attentive channel that narrows it.

## Where the photo goes, and its default

Before the name on line 1: a 24px circle (`.ph`, `border-radius: 99px`, `object-fit: cover`), 4px before the name, raised 3px so it centres on the name's x-height. It appears only when the person has published a photo. The default is its absence — the line begins with the name, and the name's hue is the mark. An own card with a photo would show the owner's photo in the same seat before "You"; without one, nothing. There is no monogram on the Feed in this direction: the monogram is the Friends tab's device for a person as an object with state; the Feed's card is an action with an author, and the author is a word.

## Standing rules — kept, bent, broken

**Bent**

- **Colour is signal** (`user-interface` skill) and the **standing objection to a chip palette**. Exception, stated precisely: one hue per friend, derived from the key, applied to the author's name text only, at fixed `oklch(78% 0.10 h)`. Never on a fill, a border, a chip, an icon, the verb, or any other text; never at another lightness or chroma. The primary's band is excluded from the derivation so You stays the only primary name. The health palette is still nowhere: these are pastels at one fixed lightness and chroma with no state meaning, and no state colour appears on the page for them to be confused with.
- **UIDR-045 rule 3** (own = the word You in the primary). Amended: You at 16px semibold as the card's first line, and the own card's border in the primary at 40% alpha (`.own-border`'s 30% raised one step; the You card on the Friends tab is the precedent). Still no fill, no bar, no tile.
- **UIDR-038 rule 3 / UIDR-045's anatomy** — the time column. Kept as an element, re-seated: the time is at the card's foot, right, on the seat's line; the sentence still never carries it.
- **UIDR-038's *wall of watching***. The page is a lattice of artwork, which is the shape that anti-pattern names. Exception: every item is an action, not a title — the author's sentence is its first line and the poster is 17% of the card's area beside 432px of text. A title grid shows what people watched; this shows who did what.
- **The name's weight**: the anatomy says medium; the direction's name is semibold. 500 at 16px in a pastel did not carry against the 18px title; 600 does.

**Kept**

- UIDR-038 rule 2 (flat, newest first, one entry per action); the *title-first row*, *grouped rows*, *state as decoration*, *social-network chrome*, *hover jump* and *day dividers* anti-patterns — the border marks authorship, not toolbar state; there are no tiles at rest, no counts, no handles; the card's height is constant.
- UIDR-033: each card's artwork is its own title's poster; no backdrops, no band of another title.
- UIDR-012: images eager, no lazy loading.
- UIDR-045: the scope pill, the entry rule, the toolbar's slots, the modal for withdrawal.
- The text alpha floor at 55%; the 120ms fade ceiling; dark theme, system fonts; PD/CC titles only.

**Broken**: nothing knowingly.

## Page width; the Watchlist and Friends tabs

The Discovery page opts out of the 1280px container as a whole, not the Feed tab alone, so the tab strip and the pill sit at the same x on every tab and nothing moves when the tab changes. The Watchlist tab's title cards are poster-led already and take the same `minmax(560px, 1fr)` lattice; the Friends tab's person cards are already a grid and fill the width the same way. All three tabs become lattices under one strip. The pill's seat at the right end of a 1820px strip is far from the tabs; that is where Linear and Home put view controls, and the pill is the only element on that edge.

## At 3 rows and at 300

At three cards: one row of three under the strip at 1920 (two and one at 1280), then the ground. `auto-fill` makes no placeholder cells, so a short Feed is a short shelf, not a grid with holes. The cards are the same 208px they are in a full page, so the shelf does not look shrunk.

At 300 cards: 100 rows of 224px pitch, about 22,400px (the shipped list at 300 rows is about 35,000px). The lattice is level all the way down because every card is 208px; the three time columns at the card feet are the orientation; Show older windows the list as it does today. What accumulates at 300 is sameness — 300 identical frames with different posters — which is the direction's texture and its cost: the Feed at 300 reads as a poster wall with sentences, not as a diary.

## The 1280 and 2560 checks

- **1280×800**: two columns of 582px; the text block is 418px (about 52 characters at 15px); three rows show, the third cut at the fold. The h1, the three tabs and the pill fit on their lines with room. Nothing reflows inside a card.
- **2560×1440**: four columns of 603px; the text block is 439px; five full rows show (twenty cards) with Show older and the next state's strip below. The poster at 120×180 still reads at this density; the four time columns stack cleanly. The lattice does not get wider than it should because the column count, not the card width, absorbs the extra width.

## Trade-offs

- **A listing card is mostly air.** Two text lines beside a 180px poster leave about 100px empty between the title and the foot. The two-corner anchoring makes it read as composed rather than unfilled, and the space is the seat's home on hover, but a reviewer who wants density will see it. Shrinking the poster would trade the presence the round asks for; this direction keeps the poster.
- **Time reads left to right within a row.** The gallery convention (Steam's activity, Letterboxd's grids), argued in decision 4; a reader used to the list's single time column has to learn that a row is a time band.
- **Hue is not identity at thirty.** Stated above. This direction's device is honest about narrowing rather than naming; the tile directions name but cost a circle per card.
- **The own border is quiet.** 40% on glass is visible at 1:1 and easy to miss at a glance; raising it further would make the You cards the loudest objects on the page. The word You in the primary does most of the work.
- **Sixteen `backdrop-filter` cards.** The house `.glass` tier blurs; on a page of 16–20 cards that is 16–20 blur layers. If it costs on the owner's GPU the `.inset` tier (no blur, same tokens otherwise) is the drop-in.
- **Sameness at scale**, above.

## Sizes, alphas and gaps

| Element | Value |
|---|---|
| Page | `.content{max-width:none}`; main padding 24 (base) |
| Lattice | `repeat(auto-fill, minmax(560px, 1fr))`, gap 16 both axes; 3 × 596 at 1920, 2 × 582 at 1280, 4 × 603 at 2560 |
| Card | padding 14, radius 14, `--glass-bg` / `--glass-border` / `--glass-shadow`, blur 12; height 208; row pitch 224 |
| Card hover | background `oklch(24% 0.02 264/.55)`, border `oklch(90% 0.005 264/.14)` |
| Card, own | border `oklch(72% 0.14 264/.4)` |
| Card, cursor | `outline: 2px solid var(--p)`, offset −1 |
| Poster | 120×180, radius 6, border 1px `oklch(100% 0 0/.08)`, shadow `0 8px 20px oklch(0% 0 0/.55)`; poster → text gap 16 |
| Poster, empty | 120×180, `oklch(93% 0.01 264/.1)`, radius 6 |
| Text block | 432px at 1920 (418 at 1280, 439 at 2560); min-height 180 |
| Line 1 | line-height 22; name 16px 600 `oklch(78% 0.10 h)` / You `var(--p)`; verb 15px `oklch(93% 0.01 264/.72)`; glyph 13px, `vertical-align: middle`, 2px left margin, heart `var(--love)` |
| Photo seat | 24px circle, 4px before the name, raised 3px |
| Line 2 | margin-top 2; title 18px 600 `var(--bc)`, line-height 25, ellipsis; year 13px at 55%, 8px gap |
| Line 3 | margin-top 6; 15px/1.5 at 70%; clamp 4 (90px) |
| Foot | height 20, `margin-top: auto`; seat → time gap 14; time 13px at 55%, tabular, line-height 20 |
| Toolbar | items 13px at 70%, height 20, padding 0 6, radius 6, gap 2, first item pulled 6px left; icons 14; hover 92% on `oklch(93% 0.01 264/.07)`; on-state 92%; Ignore `margin-left: auto` |
| Plain states | 13px at 60%; Downloading hairline 3px at 55% over 12%, 3px below the word |
| Seat fade | opacity 0 → 1, 120ms |
| Show older | ghost button, padding-top 16, −6px left |
| Empty state | headline 16px 600 / 23; body 14px/1.5 at 70%, 56ch, margins 6 above 14 below; ghost action −10px |
| Tab strip | base `.tabs`; `.seg` `margin-left: auto` |
