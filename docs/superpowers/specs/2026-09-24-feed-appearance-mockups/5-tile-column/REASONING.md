# 5 · Tile column — reasoning

Deliverable: `index.html` (links `../base.css`, art from `../art/`). Rendered with `page-shot` at 1920×1080 in the app frame (52px sidebar, 24px main padding, 1280px left-aligned content), then at 1280×800 and 2560×1440; every state in the brief is on the one page under a `.state` label. Written after the third render, from what is on the page.

## Style

The shipped list surface with its bones untouched: one inset (`.inset`, 12px radius), rows a hairline apart (8% alpha), the poster left, three text lines, the relative time in a 72px column down the right edge, the toolbar in its 20px seat at the foot of the text block. Three changes, and only three.

1. **A 56px tile column** on the row's left holds the identity tile: the Friends tab's 40px monogram, plus a 16px gap to the poster. The tile is drawn on the first row of an author's adjacent run and the cell is left empty on the rows that follow, so a prolific friend reads as one tile over a block of rows — the chat-client rule. Own rows: the tile filled with the primary, the initial in white.
2. **The poster at 80×120** (from 56×84), 6px radius, the base's 1px 8% inner border, a 0 2px 10px shadow at 45% black.
3. **The title's backdrop as a glow** behind the poster: a 200×176 box centred on the poster (offset −60, −28), the backdrop `center/cover`, `blur(16px) saturate(1.2)`, opacity .7, masked with `radial-gradient(closest-side, #000 25%, transparent 100%)` so it has no edge, and painted at `z-index:-1` inside the row's own stacking context (`isolation:isolate`) so it sits above the row's hover fill and under the tile and the text. The visible halo is about 140px wide and ends on the row's own edges. The colour is whatever the backdrop is: warm behind Charade, cool behind Sintel, near nothing behind Nosferatu. Nothing about state, hover or authorship changes it.

Type scaled to the taller row: line 1 at 16px/24 (72%, the name at 500 weight and 92%), the title at 18px/26 semibold as the row's one confident line, the year at 13px/55%, the review text at 15px/22 at 70%, capped at 72ch and clamped at four lines, the time at 13px/24 at 55% with tabular figures. The sentiment glyph is 14px, `vertical-align: middle`, in the text run.

Colour: the artwork's own (poster and glow), the rose heart, the primary on You (tile and word) and on interaction (tab underline, pill, cursor ring). Nothing else.

## Decisions

1. **The tile column is 40 + 16, not 8 + 40 + 8.** The tile sits on the row's left padding edge (16px from the surface edge) with a 16px gap to the poster, so the tile, the poster and the text share the same left rhythm as the rest of the app: content starts at the padding, gaps are 16px. Centring a 40px tile in a 56px cell would have put it on a 24px offset that nothing else on the page uses.
2. **The tile is top-aligned with the poster.** Its centre falls at 32px from the row's top, between line 1 and line 2 (whose block is 50px tall). It reads as belonging to the sentence without hanging off the hairline.
3. **A run is a property of adjacent rendered rows.** `run_start?` is true when the row's author differs from the previous rendered row's author, or the row is first. It is computed over the list as it will be drawn — after the scope filter, after any page has been appended — in one pass. The cell is always 56px; only its content varies. Nothing groups, nothing re-sorts, no heading appears: UIDR-038 rule 2 stands.
4. **The name stays on every row.** Chat clients drop the name on continuation lines; the Feed's line 1 is a sentence ("Nick wants to watch") and cannot lose its subject. The tile says *run* and *own*; the name says *who*.
5. **The glow box is larger than the visible glow.** A 128×144 box with an 18px blur was invisible (the blur pulled transparency in from outside the box, then the mask cut what was left). The 200×176 box puts the blur's falloff outside the mask's visible ellipse, and the box's vertical extent ends exactly on the row's edge (12px padding above and below the 120px poster), so the mask reaches zero on the hairline and no row tints its neighbour. `overflow:hidden` on the row is a guard, not the mechanism.
6. **Opacity .7, tried against .55.** At .55 Charade's halo was a whisper and Sintel's was gone; at .7 the halo reads at a glance on mid-tone art and still reads dark. The bright backdrops (Big Buck Bunny) are the ceiling case and stay soft.
7. **The seat stays at the foot.** I considered seating the toolbar directly under the text so it hugs what you are reading. Rejected: the seat's height above the row's bottom would then vary by row kind (listing vs review), which is the hover-jump's cousin — the seat moving between rows. At the foot, List and Download sit on the poster's bottom edge and Ignore on the time axis at the row's bottom-right corner: the four corners of the row's frame.
8. **The toolbar seat spans under the time column** (round 3's device): Ignore lands on the same right edge as the time.
9. **Hover is a 5.5% fill** on the row, no transition on the fill, the toolbar's 120ms opacity fade the only animation. The glow is under the fill's stacking order but the fill is imperceptible over it.
10. **The cursor ring** is 2px primary at `outline-offset:-2px`, following the surface's radius on the first and last rows (`border-radius` on `:first-child`/`:last-child`), so a ring on a corner row does not poke out of the inset.
11. **The tab strip centres on the pill.** The `.seg` pill is 36px tall; the tabs get 9px top and 7px bottom padding and `align-items:center`, so the tab text and the pill's options share a centre line and the underline sits at the tab's foot.
12. **Empty state on the reading edge**: headline and body start where every row's text starts (168px in from the surface edge). It looks indented on a surface with no posters, and that is right — it is where text lives on this surface.
13. **The count is omitted at zero** (You-empty reads "Feed").

## The author mark

**At three friends.** The tile column is a column of monograms — C, N, B, S, A, F — and a filled primary Y wherever the row is yours. Own rows are pre-attentive by *shape and fill* (a solid disc among tinted ones), not by the hue of a three-letter word; the word You in the primary is the second channel, kept from UIDR-045 rule 3. One friend is told from another by the letter and by position, and a friend who acts several times in a row reads as one block under one tile.

**At thirty.** The letters repeat — a roster of thirty shares initials — so the tile is not a unique identity at thirty and does not claim to be. What it gives at thirty is unchanged: own versus friend at a glance, the run structure, and the initial as a first-pass filter; the name in line 1 remains the identity, as it is on the Friends tab. A photo, when a friend publishes one, makes the tile unique. A per-person hue would make the monogram unique at thirty; that is direction 2's device and this direction does not borrow it.

## The photo: where it goes and its default

The identity tile *is* the photo slot. Two states, one element: the monogram (default, and what ships) and a circular photo (`object-fit: cover`, `object-position` per image). Shown: Ada with a photo (state 8), the monogram everywhere else. An own tile: filled primary with a white initial; an own tile with a photo: the photo in a 2px primary ring (state 8 · continued) — the You card's `.own-border` precedent lifted to a ring, so an own row with a photo is still own at a glance. The design doc's model note fits this exactly: `Discovery.IdentityTile` renders both states on both tabs, from a photo URL or nil on `Person` and `FeedEntry`.

## Runs at the window's edges

- **A Show older page beginning mid-run.** The appended page is rendered as part of the one list, so the first appended row compares with the last row already shown; if the author is the same, its cell is empty and the run continues across the page boundary. Computing runs per page would draw a second tile mid-run; the rule is a function of the ordered list, so it is not computed per page.
- **A new row arriving above a run's first row.** It is prepended. If its author matches, the new row takes the tile and the former first row's cell empties — a swap of the cell's content at the same row heights, so nothing below moves; the row's height is set by the poster and the text, never by the tile. If the author differs, the new row gets its own tile and the run is untouched.
- **A row leaving** (an ignored title, a withdrawn review) can make two rows by one author adjacent; the lower one's tile empties. Same rule, same pass.
- **Scope.** Runs are computed over the scoped list. Under You every row is yours: one run, one filled tile at the top, empty cells below (state 3). Under Friends, Nick's two rows stay adjacent and keep one tile.

## Requirements mapping

| Brief item | How it is met |
|---|---|
| Line 1: author medium weight, verb, glyph; second person on own rows | 16px/24 at 72%; name 500 at 92%; You in the primary; "You reviewed", "You want to watch"; glyph 14px inline |
| Line 2: title semibold + year | 18px/26 600 + 13px at 55% |
| Line 3: review text, clamped | 15px/22 at 70%, 72ch, four-line clamp |
| Relative time in its own place | 72px right column, 13px/24 at 55%, tabular figures; never in line 1 |
| Poster, real artwork, size named | `../art/<slug>-poster.jpg` at 80×120 |
| Toolbar: fixed seat, hover/cursor only, height constant | 20px seat at the foot, opacity 0 → 1, 120ms; row height set by poster/text |
| Friend's row: List · Download · Ignore; Listed filled; Tracking; Downloading hairline; In library | States 5 and 5 · continued |
| Own row: List · Download only, no Ignore, no Delete | States 1, 3, 6 |
| Whole-row click; names not links | `cursor:pointer` on the row; names are spans |
| Scope: the house `.seg` pill on the tab strip's line at the right; count follows scope | Feed 16 / 11 / 5; Friends 30 |
| Glyphs: heart in `--love`, thumbs up, thumbs down, none | Round 3's sprite |
| Identity tile: both states; what an own tile is | Monogram default; photo in state 8; own = filled primary; own + photo = ring |
| Sixteen rows, newest first, own at 2/6/9/13/16, rows 3–4 a run | State 1 |
| Title state per title | Charade: Listed · In library on rows 2 and 3; Pioneer One: In library on 5 and 11; Big Buck Bunny: Listed on 6 and 7 |
| State 1 Everyone + Show older | Sixteen rows, then the ghost button on the reading edge |
| State 2 Friends | Rows 1, 3, 4, 5, 7, 8 |
| State 3 You | The five own rows, one run |
| State 4 You, empty | The brief's copy; one ghost action |
| State 5 friend hovered | 5.5% fill, List · Download · Ignore |
| State 6 own hovered | Listed (filled) · In library |
| State 7 cursor | 2px primary ring, offset −2 |
| State 8 photo | Ada with a circular crop of `one-step-beyond-backdrop.jpg` |
| State 9 no artwork | `.poster-empty` at 80×120, no glow |
| UIDR-012 eager images | Plain `<img>`, no `loading=lazy` |
| No text below 55% except separators and icons | Floor is 55% (time, year, state keys); toolbar states 60% |
| No chips, badges, bars, day dividers, group headers, entrance animation, light theme, real titles beyond `art/`, hover height change, JS | None; the only transition is the toolbar's opacity; no `<script>` |

## Rules kept, bent, broken

| Rule | Status | The exception, precisely |
|---|---|---|
| UIDR-045 rule 3 — an own row differs by the word You and the second-person verb; no border, tint, marker or badge | **Bent** | One marker, in one place: the identity tile's own state (filled primary, white initial) in the tile column. The row body keeps rule 3 unchanged — no border, tint or badge on the body; the word stays. |
| UIDR-045 rule 5 — one list surface, hairlines, the time column | **Kept** | — |
| UIDR-038 rule 2 — one entry per action, newest first, flat; no grouping, dividers, re-sorting | **Kept** | A run is a rendering property of adjacent rows (`run_start?`); nothing groups, nothing re-sorts, no heading. |
| UIDR-038 rule 3 — "no avatar"; *social-network chrome* — avatars, handles, reactions, counts | **Bent** | The tile is the app's own person device (the Friends tab's monogram), in its own column outside the row body, defaulting to a letter. No handles, counts, reactions, and no photos the app does not have; the photo state is the space for a future replaceable profile event. The anti-pattern's target — a photo slot as row chrome — is not built. |
| UIDR-038 *state as decoration* | **Kept** | The glow is the title's artwork, constant across every state; List/Download/Ignore, own, hover and cursor never change it. |
| UIDR-033 — artwork when the artwork is the page's subject; no bands | **Kept in substance** | A row's own title artwork is that row's subject, and its poster was already permitted; the glow is the same title's backdrop, confined to a masked ellipse behind that poster, never a band, never another title's. No page-level artwork surface is added. |
| Colour is signal | **Kept** | Colour on the page: the artwork's own, the rose heart, the primary for You and for interaction. The tile adds a *shape* channel to the own mark, so it no longer rests on hue alone — objective 1's "a channel besides hue on a small word". |
| One anatomy for every author (objective 3) | **Kept** | Every row has the 56px cell; its content is a property of the row (`run_start?`, `own?`, photo or nil), rendered by one component. |
| Toolbar contract (objective 4) | **Kept** | Same slots, same seat, height constant. |
| Text below 55% | **Kept** | — |

## Page width, and the other tabs

**1280px, left-aligned.** A list wants a measure: at full width a 1920 row would put 1500px of body under two lines of text and the time a screen away from the name. At 1280 the body is 1008px, the review text at 72ch (~540px), and the name, the title and the time sit within one glance. The row's horizontal budget: 16 pad + 56 tile column + 80 poster + 16 gap + 1008 body + 16 gap + 72 time + 16 pad.

The Watchlist and Friends tabs share the 1280 column (from 896). The Watchlist's rows take the width and their text gets room. The Friends grid should gain columns at 1280 rather than the cards growing — a PersonCard's monogram, presence line and five-poster strip are sized for a card, not a band — and the monogram on those cards is now the same element the Feed draws, so recognition carries between the tabs (Problem 6).

## At 3 rows and at 300

At three rows the list is three rows under the strip, about 430px, with no Show older; the surface's radius and the hairlines bound it and a short list looks short, not sparse. Three tiles or fewer (one, if the three are yours) and three posters with their glows are enough colour for the page to have a face.

At 300 rows the column is about 45,000px. What holds it together is the same three verticals as before — tiles, posters, times — with two things the shipped list did not have: the tile column breaks and rejoins at every change of author, so the eye reads authorship as a rhythm without reading names, and each poster carries its own colour, so 300 rows are not 300 of the same tone (Problem 3). Runs make the column quieter, not busier, as the roster's prolific friends stack. The cost at 300: 6.5 rows per fold at 1920 against about 9 on the shipped list, because a row grew from 108 to 144px.

## 1280 and 2560

**1280×800.** The content shrinks to the available 1180px (1280 − 52 sidebar − 48 main padding); the body is 908px, the pill still sits on the strip's line, and four and a half rows fit the fold. Nothing wraps or reflows; the 72ch measure is untouched.

**2560×1440.** Raw, the 1280 column is half the width and the right half is scrim — nine rows in the fold. In the app the UI scale is screen-derived (2560 / 1920 ≈ 1.33), so the column renders at about 1700px, two thirds of the width, with about seven rows per fold. The mockup has no scale factor, so the raw shot is the worst case; the composition at 2560 is the app's scale, not the page's.

## Trade-offs

- **Listing rows carry air.** Two lines of text against a 120px poster leave about 50px between the title and the seat. The toolbar fills the bottom 20px on hover; the middle is empty. The poster and its glow earn the height; a reader used to the 108px rows will see space.
- **The You scope is one tile and a column of empty cells.** Every row is yours, so the rule gives one filled tile at the top and 56px of nothing on every row below. Honest, and quiet; but under the audit view the tile column does no work.
- **The glow is only as strong as the artwork.** Bright backdrops (Big Buck Bunny) glow; dark ones (Nosferatu, Sintel) barely do. The page's colour is uneven by design and the eye will catch on the bright rows first. That is the artwork deciding, not state, but it is a bias toward bright titles.
- **At three friends, runs are rare.** Sixteen rows hold one run of two. The tile column's rhythm pays off as the roster grows and friends act in bursts; today it is mostly one tile per row, and a page of alternating authors is a column of monograms.
- **A second element per row.** The tile is a 40px disc on every first-of-run row, against the shipped page's nothing. It is the app's own device, but it is more chrome than the word was.
- **Fewer rows per fold** (6.5 at 1920 against about 9).

## Data note

Times, titles and states follow the brief's table; the Friends state's sixth row is Ada (row 8), the sixth friend row in order. State 5 · continued uses Femi on Tears of Steel for the Downloading case (a friend's row with the Downloading state and Ignore), since the brief's Downloading title is on an own row; Coffee Run, a spare title, stands in for the no-artwork row.
