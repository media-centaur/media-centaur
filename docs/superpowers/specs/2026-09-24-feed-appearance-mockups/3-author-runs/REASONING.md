# 3 · Author runs — reasoning

Deliverable: `index.html` (links `../base.css`, art from `../art/`). Rendered with `page-shot` at 1920×1080 in the app frame (52px sidebar, 24px main padding, the 1280px left-aligned column), then at 1280×800 and 2560×1440; every state in the brief is on the one page under a `.state` label. Three render passes: the first set the structure, the second tightened the rhythm and dropped the primary from the word "You", the third tuned the own tint and the photo crop.

## Style

One inset list surface, runs a hairline apart. A **run** is one author's adjacent actions: a heading — the identity tile at 40px, the name at 17px semibold, the run's newest time at the right edge — and beneath it the run's actions as **poster cards**, three across, newest first, wrapping. A run of one is one card under its heading. An own run sits on a primary tint with the tile filled; a friend's run sits on the plain inset with the monogram. The card is poster-left (96×144, lifted by a shadow), three text lines to its right, the toolbar seat at its foot on the poster's bottom edge. Dark slate, system fonts, no glass beyond the inset. Colour: the rose heart, the primary on the own tile, the own tint, the cursor ring, the tab underline and the pill's chosen option; everything else is the neutral ramp.

The Steam activity feed and every chat client show the person once per adjacent run rather than on every item; Letterboxd and Trakt lead with the identity tile. This direction takes both: the tile once, at the run's head, and the actions as artwork under it.

## Sizes, alphas and gaps

| Element | Value |
|---|---|
| Column | `.content` 1280px, left-aligned (base default); at 1920 it spans x 76–1356 |
| List surface | `.inset` background `oklch(18% 0.017 264/.4)`, radius 12, `overflow:hidden` so the first and last runs take the radius |
| Run | padding 12px 16px 14px; 1px hairline at 8% between runs; height for a run of one card: 234px (12 + 40 + 8 + 160 + 14) |
| Own tint | `oklch(72% 0.14 264/.08)` filling the run edge to edge between its hairlines (pass 3 raised it from 7%) |
| Heading | flex, `align-items:center`, height 40px; tile → name gap 12px |
| Identity tile | 40px circle; monogram = `.mono` (primary at 15%, initial 16px semibold in the primary); own = filled `var(--p)`, initial in `oklch(13% 0.02 264)`; photo = `<img>` cover, `object-position:50% 34%`, `transform:scale(2.2)` from origin 50% 34%, clipped by the circle |
| Name | 17px / 600 / `oklch(93% 0.01 264/.92)`, `line-height:1`; "You" in the same neutral (pass 2 tried the primary — three primaries on one band was one too many; the filled tile carries the hue) |
| Time | 13px at 55%, tabular figures, `margin-left:auto` — one x for every run's time |
| Strip | `margin:8px 0 0 44px` (52px indent minus the card's 8px padding, so the poster's left edge sits on the name's x); grid `repeat(3, minmax(0,1fr))`; gap 8px rows × 12px columns; at 1920 a card is 393px |
| Card | padding 8px, radius 10, `cursor:pointer`; transparent at rest; hover/`.hovered` fill `oklch(93% 0.01 264/.065)`; `.cursor` ring `outline:2px solid var(--p); outline-offset:-1px` (the ring follows the radius) |
| Poster | 96×144 (`img.poster`, 2:3, 1px border at 8%), `box-shadow:0 8px 20px oklch(0% 0 0/.5)`; poster → text gap 14px |
| Text block | 393 − 16 − 96 − 14 = 267px, about 38ch at 14px; `min-height:144px` so the seat sits on the poster's foot whether or not there is review text |
| Line 1 | the verb and the glyph, 15px/22px at 72%; glyph 13px, `vertical-align:middle`, heart in `--love` |
| Line 2 | title 16px/23px semibold at 100%, year 13px at 55%, baseline-aligned, gap 8px |
| Line 3 | 14px/1.5 at 70%, `-webkit-line-clamp:3`, margins 4px above and below |
| Toolbar seat | 20px, `margin-top:auto`, `opacity:0 → 1` in 120ms; verbs 13px at 70% in 20px pills (6px side padding, radius 6, 7% fill on hover); plain states at 60%; Downloading's 3px hairline 3px under the word, 55% done / 12% rest; Ignore on the card's right edge via `margin-left:auto` |
| Show older | ghost button on the reading edge (the name's x: 16 + 52 − 10px button padding) |
| Empty state | headline 16px semibold, body 14px at 70% with a 56ch measure, one ghost action; padding 28px 16px 32px 68px |

## Decisions

1. **The run is a fold over the flat list, not a query.** The list stays one row per action, newest first, exactly as UIDR-045 fetches it. Rendering walks it once and starts a new run whenever the author changes. Nothing is re-sorted, nothing is merged across a different author, and a run's cards are the rows in their list order. Runs are computed over the *scoped* list: under Friends, the own rows are gone, so two friend rows that were separated by yours become adjacent and, if by one author, one run. What is a run depends on what is listed, which is the honest answer.
2. **A run breaks after a day.** A run joins the next adjacent row by the same author only when it is within 24 hours of the row before it. The heading carries one time; a run must be a span that one time can stand for. Without the bound the You scope — every row own — would collapse to one heading "You · 1h ago" over five cards spanning three weeks, and UIDR-045's audit view would lose its time axis. With it, state 3 is five runs of one, each on the tint, and the axis reads down the headings. Nick's rows 3–4 (both 2h ago) still join.
3. **The name and the time move to the heading; the card keeps the verb.** Line 1 on a card is the verb alone, lowercase, continuing the heading's name: "Cleo — wants to watch — Sintel"; on an own card the second person carries through: "You — want to watch — Big Buck Bunny". The name is never repeated on a card, and the heading holds nothing but the tile, the name and the time — no counts, no summary.
4. **Three across, wrapping, not a horizontal scroll.** A horizontal strip inside a vertical feed hides actions behind a second scroll axis and fights the mouse wheel. Three columns at 1280 give a card a 267px measure — 38ch, enough for a review to read in its three lines — and a run of ten wraps to four lines under one heading, still one unit. At 1280×800 the column is 1180px and a card is 360px (32ch); the review text wraps a line earlier and nothing else changes.
5. **The poster on the name's x.** The strip is indented under the name (the chat-client rule: the tile hangs in its own gutter), and the card's 8px padding is subtracted from the indent so the poster's left edge and the name share x = 52 inside the run. Two verticals hold the run: the tile gutter and the content edge.
6. **Own = the tile's fill and the surface's tint, not the word's colour.** The filled tile is the monogram's own state (one component, one property). The tint extends the You card's `.own-border` precedent from a 30% border to an 8% fill. Together with the second-person verb that is three channels — shape (filled vs tinted circle), surface, words — none of which is a hue change on a small word. The word "You" stays neutral.
7. **The card is the click target and the cursor's unit.** Whole-card click opens the title modal; the heading is not a target and the name is not a link. The keyboard cursor lands on a card; → moves along the strip, then into the card's toolbar; ↓ moves to the first card of the next run.
8. **Hover is a fill on the card, in place.** 6.5% neutral with the card's radius, on top of the tint on an own run; the toolbar fades in in the seat; the strip's height never changes.
9. **The seat sits on the poster's foot** for every card, listing or review, because the text block's `min-height` is the poster's height and the seat is pushed to the bottom. In the shipped row the seat floats with the text; here it is a fixed line under every card.
10. **Sentiment glyph sizing follows the app** (commit 80d46627): inline SVG, `vertical-align:middle`, 13px in the 15px verb line.
11. **The count is omitted at zero.** "Feed", not "Feed 0", in state 4.

## Requirements mapping

| Brief item | How it is met |
|---|---|
| Sixteen rows newest first, own at 2, 6, 9, 13, 16 | State 1 has all sixteen in order as fifteen runs; rows 3–4 are Nick's run of two |
| Feed 16 · Friends 11 · You 5; Friends tab reads 30 | Tab counts per state; "Friends 30" on every strip |
| Scope on the house pill at the right of the tab strip | `.seg` with `margin-left:auto` on the `.tabs` line, sunk 2px onto the underline's baseline |
| Line 1: author medium, verb, glyph | Author = the heading's name (17px semibold); verb + glyph = the card's line 1 |
| Own rows in the second person | "want to watch", "reviewed" under the You heading |
| Line 2 title semibold + year; line 3 text clamped | 16px 600 + 13px at 55%; 14px at 70%, three-line clamp (named) |
| Relative time in its own place, never in line 1 | The heading's right edge, one x for every run |
| Poster from `art/`, size named | `<slug>-poster.jpg` at 96×144 |
| Toolbar in a fixed seat, height never changes | 20px seat at the card's foot, opacity only |
| Friend's row: List (Listed filled; Tracking above List) · Download (Downloading hairline / In library) · Ignore last | State 5: Metropolis List · Download · Ignore; 5 · continued: Charade Listed · In library · Ignore, Spring Tracking · Download · Ignore |
| Own row: List · Download only; no Ignore, no Delete | State 6: Listed · In library; 6 · continued: List · Downloading (hairline) |
| Whole-row click; names not links | The card has `cursor:pointer`; the heading is plain spans |
| Glyphs: heart in `--love`, thumbs up/down, nothing for none | Round 3's sprite, unchanged |
| Identity tile: monogram default and photo state; what an own tile is | Monogram on every friend; photo on Femi (state 8, a circular crop of `one-step-beyond-backdrop.jpg`); own = filled primary tile with the initial |
| State 1 Everyone + Show older | Fifteen runs, then the ghost button on the reading edge |
| State 2 Friends: first six rows, own gone | Cleo, Nick ×2, Bob, Sam, Ada — five runs |
| State 3 You: five own rows | Five own runs of one (decision 2) |
| State 4 You, empty | The brief's copy and one ghost action, on the reading edge |
| States 5–7 show the group's unit | Each is a full run (heading + strip), Nick's run of two where a second card at rest is useful |
| State 7: 2px primary ring | On the card, offset −1px, toolbar shown |
| State 9: no artwork | `.poster-empty` at 96×144, 10% slab; the card keeps its size and its seat |
| UIDR-012 eager images | Plain `<img>`; in the app `loading="eager" decoding="sync"` (MC0016) |
| No chips, badges, bars, avatars with photos we do not have, day dividers, entrance animations, light theme, real titles beyond `art/`, text under 55% | None; the only transition is the seat's 120ms fade; the lowest text alpha is 55% (time, year, keys) |

## The author mark

**At three friends** (six in the window) the tile letters are all distinct — C, N, B, S, A, F — and the tile plus the 17px name is read before the card is. The own run is unmistakable from across the room: the filled tile, the tinted band, the word.

**At thirty** the monogram's letter collides (three S's, two A's) and the tile says only "a friend", pre-attentively; the name at 17px semibold is the identifier, and it is the largest type on the page, in a fixed place, once per run. The strong friend mark at thirty is the photo: a friend who publishes one is recognised at 40px the way the Friends tab already recognises them. The run device itself scales the other way — a roster of thirty interleaves more, so runs are shorter, and the device's payoff (a binge as one heading over a strip) is rarer. What holds at thirty is the heading rhythm: name, name, name down the reading edge, own bands as landmarks.

**Where the photo goes and its default.** The identity tile. Default is the monogram; when the person has published a photo the tile is the photo, and nothing else on the run changes (state 8). An own tile with a photo is the photo — the tint and the word carry the own mark, so no ring is added over the picture. The photo is a circular crop with `object-fit:cover`; in the app the person's own crop position replaces the `object-position` and `transform` used here to find the face in a backdrop.

## Standing rules: kept, bent, broken

| Rule | Status | Exception, stated |
|---|---|---|
| **UIDR-038 rule 2** — one entry per action, newest first, flat; no grouping, day dividers or re-sorting | **Bent** | The list is still one row per action in time order and is never re-sorted. A run is a rendering fold that joins rows that are *already adjacent* and by one author, within a day; it inserts a heading and lays the joined rows side by side. No row moves relative to another. The exception is the heading and the side-by-side layout, nothing about order or membership. |
| **UIDR-038 anti-pattern *grouped rows*** — "one row per title, re-sorted on the next friend" | **Named exception** | That pattern merged by *title* and re-sorted on any friend's later action, so a row's position depended on other people. This joins by *author* and only when adjacent; a run's position is its newest row's position and cannot move because of anyone else's action. Two rows on one title by two friends (rows 6 and 7, Big Buck Bunny) stay two cards in two runs. |
| **Group headers** (DESIGNER.md: none that are not the direction's stated device) | **Kept** | The run heading is this direction's stated device and the only header. No day, week or title headers. |
| **UIDR-045 rule 3** — one anatomy; own = the word You in the primary and the second person; "no border, tint, marker or badge" | **Broken, twice, on purpose** | (a) The own run's surface is tinted (8% primary), extending the You card's `.own-border` precedent to a fill. (b) The own tile is filled. The anatomy is still one: every run has tile · name · time · strip, and own differs by two *properties* (the tile's fill, the surface's tint) of the same component, never a second component. The word drops its primary colour. |
| **UIDR-045 rule 5** — one list surface, rows a hairline apart, the time in a right column | **Bent** | One inset surface, hairlines between *runs* instead of rows. The time keeps one x at the right edge, on the heading rather than on every row. |
| **UIDR-038 rule 3** — an entry shows name, action, title (poster, name, year), text, time; the sentence is the first line | **Bent** | The name and the time move up to the heading; the card shows action, title, text. A row inside a run of two or more does not carry its own time — the run's newest time stands for it, with decision 2 capping the drift at a day. |
| **UIDR-038 *social-network chrome*** — avatars, handles, reactions, counts | **Named exception** | The identity tile is `Discovery.PersonCard`'s monogram, the app's own person device, now shared by both tabs (the design doc's objective 6). No handles, reactions or counts anywhere; the heading carries only name and time. The photo state is the owner's note made a place for, using no image we do not have. |
| **UIDR-038 *state as decoration*** | Kept | The tint is authorship, not state; no chips or markers on cards. |
| **UIDR-038 *title-first row*** | Kept, with a lean | The verb is still the card's first line and the name is above it; but the poster is the card's largest element and the artwork leads the eye before the words do. That is the round's objective 2. |
| **UIDR-038 *hover jump*, *day dividers*, *wall of watching*** | Kept | None. |
| **UIDR-045 rule 4** — own toolbar List · Download; withdrawal in the modal | Kept | States 6 and 6 · continued. |
| **UIDR-033** — artwork when it is the subject | Kept | Only each card's own poster; no backdrops, no bands. |
| **UIDR-012** — eager, no entrance animations | Kept | Plain `<img>`; the seat's fade is the only transition. |
| **Colour is signal** | Kept | Primary = interaction (ring, underline, pill) and You (tile, tint); rose = love; the health palette absent. |
| **No avatars with photos** (DESIGNER.md) | **Named exception** | State 8 is the brief's requested photo state, drawn from a backdrop in `art/` as the brief specifies; nothing else on the page is a photo of a person. |
| **Text floor 55%** | Kept | Time, year and scaffolding keys are the floor. |

## Show older, and a run at the window's edge

Runs are derived from the loaded rows on every render, so the window's edge is nothing special. When "Show older" appends the next page, the fold runs again over the longer list: if the first older row is by the last run's author and within a day of that run's last row, it joins that run — a card is appended to the strip (or starts a new line of it), the heading's time (the newest) does not change, and nothing above the strip moves. Otherwise a new run begins below the hairline. A new action arriving at the top behaves symmetrically: same author and within a day of run 1's newest row, and it becomes run 1's first card with the heading's time updated; the strip's cards shift one place right. Otherwise a new run is inserted above. Either way the page below the change is untouched, which is all a feed can promise.

## At 3 rows and at 300

At 3 rows the surface is three bands, about 700px, each a heading and one card; the inset frames them and a short feed looks short, not sparse. At 300 rows a roster of thirty gives roughly 250 runs, most of one card, at 234px each — about 60,000px, worse than the shipped list's 35,000px because every run of one pays for its heading. What holds it together is the heading rhythm on the reading edge, the time at one x on every heading, and the own bands recurring as landmarks. Runs of many compress it: a friend who lists eight titles in an evening is one 400px unit, not eight rows.

## The 1280 and 2560 checks

At 1280×800 the column is 1180px inside the frame; three cards across at 360px, a 32ch measure; the tab strip and the pill share the line with room to spare; the own band, the tile and the heading are unchanged. At 2560×1440 the column stays 1280px and left-aligned, so the right half of the screen is the scrim — the frame's rule for a direction that keeps the column, and this one does: a wider strip would only widen the empty right of a run of one. The composition at 2560 is the 1920 composition with more margin; the posters do not grow.

## Page width, and the Watchlist and Friends tabs

1280px, left-aligned, the base default. The Feed's list surface spans it; the tab strip and the pill are the constants above every tab. The Watchlist keeps its rows in the same inset at the same width (a longer measure for the sentence and the state), and the Friends grid gains a column of `PersonCard`s. The identity tile is the thing the two tabs now share: a person is the same 40px circle on Friends and at the head of every run here.

## Trade-offs

- **A run of one is the common case, and its band is two-thirds empty.** With three friends interleaving (this data) fifteen of sixteen rows are runs of one; at thirty friends interleaving is heavier still. The device pays only when one person acts several times in a row, which is exactly the "prolific friend" case UIDR-038 lists as a consequence — and then it pays well. The rest of the time the page is a stack of heading-plus-card bands with the card in the left third.
- **The heading costs 60px per run.** A run of one is 234px against the shipped row's 112px: about four and a half runs above the fold at 1080, not eight rows.
- **An action inside a run loses its own time.** The heading's newest time stands for the run; decision 2 caps the error at a day. The modal still shows the action's exact time.
- **No dominant element.** Nothing leads the page; the own band is the nearest thing to one. Direction 4 owns that lever.
- **Runs are unstable at their edges.** A new action can merge into run 1 and shift its cards right; a hidden own row under Friends can fuse two friend runs. Both are correct and both are visible.
- **A horizontal axis enters the nav graph.** The cursor moves card to card along a strip before it moves down; a run of ten is ten stops on one line.

## Least sure

The 24-hour bound (decision 2). It is what keeps the You scope an audit view with a time axis and stops a heading from standing for a week, but it is a rule the brief did not state, and it means two adjacent runs can carry the same tile and name back to back. The alternative — pure adjacency — makes the You scope one heading over a 3 + 2 poster grid: more striking, less honest.
