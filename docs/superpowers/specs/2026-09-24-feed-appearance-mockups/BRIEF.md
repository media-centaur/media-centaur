# Round 4 brief — the Feed's appearance: telling authors apart, and a page that pops (2026-09-24)

Round 3 chose `../2026-09-24-feed-timeline-scope-mockups/3-editorial-list`
and it shipped as UIDR-045. Read its `index.html` and `REASONING.md` for
the anatomy and the toolbar contract you inherit. Read
`../2026-09-24-feed-appearance-design.md` for the diagnosis (Problem) and
the design objectives; every direction answers that diagnosis point by
point. Read `DESIGNER.md` for how you work. This round changes the look,
not the behaviour: the scope, the entry rule, the toolbar's slots and the
modal stay as shipped.

## What the owner asked

1. **Tell authors apart at a glance.** Own rows from friends', and one
   friend from another, at a roster of thirty (three today).
2. **Make it gorgeous.** In the owner's words: "I really want this feed
   page to POP… I want people to be like… holy crap." The bar is the
   Home page (`page-shot --url http://127.0.0.1:2160/`), not the shipped
   Feed.
3. **A note, not a mandate — photos.** A person may one day publish a
   photo through the social relay; it would stay until replaced or
   removed. Nothing is built for it in this round. The design makes a
   space for a photo and a default for when there is none.

## The frame you draw

Draw the app shell so the composition is judged where it lives
(`.frame`, `.sidebar`, `main`, `.content` in `base.css`): a 52px
collapsed sidebar, `main` with 24px padding, then the page. The page's
content container is **1280px, left-aligned** — not centred — unless the
direction takes full width the way Home does (`.content{max-width:none}`).
Say which you chose and why. Build for 1920×1080; check 1280×800 and
2560×1440 once and say how it holds.

## Anatomy you inherit (UIDR-038 as amended by UIDR-045)

- **Line 1**: author (medium weight), verb, the sentiment glyph when a
  review gives one. Own rows in the second person: "You reviewed", "You
  want to watch" (never "wants"). Friends: "Cleo wants to watch", "Nick
  reviewed".
- **Line 2**: title (semibold) and year. **Line 3**: the review text when
  there is any, clamped (round 3 used four lines; name yours).
- **The relative time** in its own place, never inside line 1.
- **Poster**: real artwork from `art/` (`<slug>-poster.jpg`, 400×600;
  `<slug>-backdrop.jpg`, 1600×900). The size is yours; name it.
- **Toolbar**: shown only while the row is hovered or holds the cursor,
  in a fixed seat, the row's height never changing. Friend's row: List
  (bookmark; "Listed" filled when on your list; "Tracking" as plain state
  above List) · Download (or plain state "Downloading" with the 3px
  hairline / "In library") · Ignore last. Own row: List · Download only —
  no Ignore, no Delete; withdrawing is the modal's.
- **Whole-row click** opens the title modal (not drawn). Names are not
  links.
- **The scope**: the house segmented pill (`.seg`), Everyone · Friends ·
  You, on the tab strip's line at the right. The tab count follows the
  scope.
- **Glyphs**: love = filled heart in `--love`; like = thumbs up; dislike
  = thumbs down; no sentiment = nothing. Inline SVG symbols in the text
  run, x-height sized; copy the sprite from round 3's `index.html`.

## The identity tile

The one new element with a house precedent. The Friends tab draws every
person as a **monogram**: a 40px circle on a primary tint carrying the
name's first letter (`.mono` in `base.css`, mirroring
`Discovery.PersonCard`). Call the element the **identity tile**. It has
two states: a **photo** (a circular image) when the person has published
one, and the **monogram** default when not. A direction that uses the
tile shows both states and says what an own tile looks like (You). A
direction that does not use the tile still shows, in one state, where a
photo would go and what its default is — or argues in REASONING why the
Feed should have no place for it at all. For the photo state use a
circular crop of one of the backdrops in `art/` (`object-fit: cover`,
`object-position`); no other image source.

## Data — sixteen rows, newest first

Seven authors: You and six friends (Cleo, Nick, Bob, Sam, Ada, Femi).
The roster is thirty; the Friends tab reads **Friends 30** and only these
six appear in the window. Own rows are 2, 6, 9, 13, 16, so the counts
are **Feed 16 · Friends 11 · You 5**. Title state is per title: every
row of a title shows the same toolbar state.

| # | Row | Art slug | Time | Text / state |
|---|---|---|---|---|
| 1 | Cleo wants to watch · Sintel (2010) | `sintel` | 12m ago | |
| 2 | **You** reviewed ♥ · Charade (1963) | `charade` | 1h ago | "Saw it twice. The last twenty minutes are the whole film." · Listed · In library |
| 3 | Nick reviewed 👍 · Charade (1963) | `charade` | 2h ago | no text · Listed · In library |
| 4 | Nick wants to watch · Metropolis (1927) | `metropolis` | 2h ago | |
| 5 | Bob reviewed (no sentiment) · Pioneer One (2010) | `pioneer-one` | 1d ago | "Slow start, give it three episodes." · In library |
| 6 | **You** want to watch · Big Buck Bunny (2008) | `big-buck-bunny` | 3d ago | Listed |
| 7 | Sam wants to watch · Big Buck Bunny (2008) | `big-buck-bunny` | 3d ago | Listed |
| 8 | Ada reviewed ♥ · Night of the Living Dead (1968) | `night-of-the-living-dead` | 4d ago | "The farmhouse is the whole film. Every argument in it is still happening somewhere." |
| 9 | **You** reviewed 👎 · Tears of Steel (2012) | `tears-of-steel` | 6d ago | "Not for me. The score does all the work the script should." · Downloading |
| 10 | Femi wants to watch · Nosferatu (1922) | `nosferatu` | 6d ago | |
| 11 | Cleo reviewed (no sentiment) · Pioneer One (2010) | `pioneer-one` | 1w ago | "Fine." · In library |
| 12 | Bob wants to watch · Spring (2019) | `spring` | 2w ago | Tracking |
| 13 | **You** reviewed ♥ · The General (1926) | `the-general` | 2w ago | "Every gag is a stunt and every stunt is a gag. A century old and it still moves faster than most things made this year." |
| 14 | Nick reviewed ♥ · Cosmos Laundromat (2015) | `cosmos-laundromat` | 2w ago | "Fifteen minutes, and I thought about it for a week." |
| 15 | Sam reviewed 👍 · Carnival of Souls (1962) | `carnival-of-souls` | 3w ago | "Cheap, strange, and it gets under the skin." |
| 16 | **You** want to watch · Sprite Fright (2024) | `sprite-fright` | 3w ago | Listed |

Spare art for other states: `caligari`, `coffee-run`, `one-step-beyond`.
Rows 3–4 are a run of two by one author, on purpose.

## States to show — all on one page, each under a `.state` label

1. **Everyone** — all sixteen, then "Show older".
2. **Friends** — the first six rows with the own rows gone.
3. **You** — the five own rows.
4. **You, empty** — headline "What you review and list lands here"; body
   "A review is always shared. A title you list is shared while Share
   your watchlist is on."; one quiet action "Settings → Social".
5. **A friend's row hovered** — toolbar List · Download · Ignore.
6. **An own row hovered** — toolbar Listed (filled) · In library.
7. **The keyboard cursor on a row** — 2px primary ring.
8. **A friend with a photo** — the identity tile's photo state, or the
   direction's answer.
9. **A row whose title has no artwork yet** — no poster, no backdrop;
   the quiet fallback (a warm is pending, or TMDB has none).

States 5–9 can be single rows under their labels. If the direction
groups rows, states 5–7 show the group's unit.

## House rules

Dark slate, glass, system fonts, calm. Colour is signal: the rose heart,
the primary for interaction and for You; the health palette nowhere on
this page. No chips, no badges, no accent or edge bars, no day dividers,
no group headers except a direction's stated device, no entrance
animations (a 120ms opacity fade on the toolbar is the ceiling), no text
below 55% alpha except separators and icons, no titles beyond the PD/CC
ones in `art/`. UIDR-012: images eager, no lazy loading. UIDR-033: a
page shows artwork when the artwork *is* the page's subject — a row's
own title artwork is that row's subject; a band of an unrelated title is
not. UIDR-038's anti-patterns stand unless your direction names the one
it bends and why: wall of watching, title-first row, grouped rows, state
as decoration, social-network chrome, hover jump, day dividers.

## Precedents, and what makes Home pop

Every feed people call beautiful does four things this page does not:
it lets the artwork carry the item (Apple TV's backdrop rows, Mubi's
stills, Steam's game capsules); it gives each screen one dominant
element (a lead item, a hero, a larger first card); it sets one line in
a confident size (a name, a title, a pull quote) so the type has
hierarchy; and it layers — scrims, glass, shadow — so the page has
depth. Authorship in those feeds is nearly always an identity tile
(Letterboxd, Trakt, Steam, Spotify's friend activity), sometimes the
name alone in a colour or weight, and Steam and most chat clients show
the tile once per adjacent run rather than on every item. Cite a
precedent when it helps, but the house rules win: no photos we do not
have, no counts, no reactions, no handles.

Home (`page-shot --url http://127.0.0.1:2160/`) is the app's own
precedent: a full-bleed backdrop with the title lockup at 7xl, backdrop
cards at 453px with a gradient scrim and `.text-on-image-lg` titles,
poster rails at 170px. The Feed does not have to be Home, but it has to
belong on the same monitor.

## Directions

Each is a different structure, not a variation, and each carries a
different author-mark device so the owner can compare devices as well as
looks. Commit fully to yours; the other directions exist so that yours
can be pure.

- **`1-cinematic-rows`** — *the row carries its backdrop.* Each row is a
  wide band, about 140–160px tall, the title's backdrop filling it under
  the house scrim (dark on the left where the text sits, the image clear
  on the right — `.page-side-dim`'s recipe at row scale); the poster on
  the left at about 72×108; the three lines over the dark part in
  `.text-on-image`; the time at the right edge. The **identity tile** is
  the author mark: 36–40px at the row's far left before the poster — the
  monogram for a friend, the photo when one exists, and for You a filled
  primary tile with a white initial. Hover lightens the scrim a step and
  seats the toolbar. Argue: UIDR-033 (the artwork is the row's subject),
  UIDR-038's *social-network chrome* (the monogram is already the app's
  person device on the Friends tab; a photo slot is the owner's note),
  UIDR-045 rule 3 (own = the filled tile). Say whether the rows stay
  inside 1280 or take full width, and what the backdrop does when the
  row is narrower than 1280.
- **`2-poster-gallery`** — *the Feed fills the width as poster-led
  cards.* Full width (Home's opt-out): three columns at 1920, two at
  1280, four at 2560. A card leads with the poster at about 120×180; the
  sentence, the title, the text (clamped), the time; the toolbar seat at
  the card's foot. Reading order is newest first, left to right, then
  down — argue how the time axis still reads without a right-hand
  column. The author mark is **typographic plus hue**: the author's name
  is the card's first line at about 16px semibold, and each friend gets a
  stable hue on the name derived from the public key — oklch with fixed
  lightness (about 78%) and chroma (about 0.10), hue only varying — while
  You keeps the primary at full chroma. No tile in the row; show in one
  state where a 24px photo would sit before the name if the owner wants
  it later. Argue: the colour-is-signal rule and the standing objection
  to a chip palette (this is one hue per person on the name text alone,
  never a fill), UIDR-045 rule 3.
- **`3-author-runs`** — *consecutive rows by one author collapse into a
  run.* A run has a heading — the identity tile at 40px, the name at
  about 17px semibold, the run's newest time — and beneath it the run's
  actions as a horizontal strip of poster cards at about 96×144, each
  with its verb and glyph, its title and year, its text clamped at three
  lines; the toolbar seat at each card's foot. A run of one is one card
  under its heading. Own runs sit on a primary-tinted surface (extend the
  You card's `.own-border` precedent to a tint); friends' runs on the
  plain inset. Column inside 1280. Argue: UIDR-038 rule 2 ("flat") — a
  run only joins adjacent rows and never re-sorts; UIDR-038's *grouped
  rows* anti-pattern (that one was one row per title re-sorted by the
  next friend; this is one heading per adjacent run); UIDR-045 rule 3;
  and *group headers* (the heading is the device). Say what "Show older"
  does to a run that spans the window's edge.

- **`4-front-page`** — *hierarchy by recency: a lead, then the list.*
  The newest action is the page's dominant element: a lead card about
  1180×300 with the title's backdrop full-bleed under the scrim, the
  poster at about 140×210 over it, the sentence at about 18px, the title
  at about 28px semibold in `.text-on-image-lg`, the review text at 16px
  with room to breathe, the identity tile at 48px. Below it, the next
  two or three actions as backdrop cards in a row (about 380×170 each,
  the poster small, the sentence and title over the scrim), then the
  rest as the editorial list with the identity tile at 32px before the
  poster. The order is still newest first, flat, one entry per action:
  what changes down the page is size, not membership. Own rows: the
  filled primary tile. Argue: UIDR-038 rule 2 (flat — this is flat, with
  a size ramp), UIDR-033, UIDR-045 rule 3, and what the lead does when
  the newest action is a bare listing with no words. Say what "Show
  older" and a re-render on a new action do to the ramp (a new row
  arriving must not make the page jump).
- **`5-tile-column`** — *flat rows, the tile marks the run.* The
  shipped list surface and anatomy, with three changes: a 56px left
  column holds the identity tile (40px), drawn on the first row of an
  author's adjacent run and left empty on the rows that follow it, so a
  prolific friend reads as one tile over several rows (the chat-client
  rule); the poster grows to about 80×120; and the title's backdrop
  appears only as a soft, dark, blurred glow behind the poster (about
  120px wide, the artwork's own colour at low alpha, never a band).
  Rows stay one hairline apart in one inset surface; the time column
  stays on the right; the toolbar seat stays. Own rows: the filled
  primary tile. Argue: UIDR-045 rule 3 and rule 5 (kept), UIDR-038's
  *social-network chrome* (the tile is the Friends tab's device),
  *state as decoration* (the glow is the artwork, not state), and
  whether the empty tile cells break "one anatomy for every author".
  Say what happens to a run when a Show older page begins mid-run, and
  when a new row arrives above a run's first row.

## Deliverable

`index.html` (linking `../base.css`, images from `../art/`) and
`REASONING.md` with: style; decisions; a requirements mapping covering
every state and every anatomy item; the author mark at three friends and
at thirty; where the photo goes and its default; the standing rules the
direction keeps, bends or breaks — each named, the exception stated
precisely; the page width and what the Watchlist and Friends tabs do at
it; how it holds at 3 rows and at 300; the 1280 and 2560 checks;
trade-offs. Render your own page with `page-shot` to a scratch folder
and look at it before you write REASONING; do not commit screenshots.
