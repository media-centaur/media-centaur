# Round 3 brief — own entries in the timeline, an author scope (2026-09-24)

Round 2 chose `../2026-09-11-discovery-feed-mockups/A-poster-left-row` and it
shipped as UIDR-038. Read it for the anatomy and tone. This round changes
two things and asks for a visual step up. Each direction is a distinct
structure, not a variation; all three stay inside the house rules.

## What changes

1. **Own actions join the feed.** "You" is an author like any friend: own
   reviews and own listings, interleaved with friends' by time. Watched
   stays off the feed for everyone (the "wall of watching" anti-pattern
   holds). Only what was broadcast exists: a listing made while *Share your
   watchlist* was off is not an activity.
2. **An author scope.** A pick-one: **Everyone** (default) · **Friends** ·
   **You**. The tab count ("Feed 11") follows the scope.
3. **Presence at 1920×1080.** Today the feed is a strip of 48×72 cards in a
   768px column on an otherwise empty page. It should look composed and
   modern. The Watchlist and Friends tabs share the column, so a wider
   column is a page decision; say what width you chose.

## Anatomy — kept from round 2, one anatomy for every author

- **Line 1**: name (medium weight), verb, the sentiment glyph when a review
  gives one, a separator, the relative time. Glyphs: love = filled heart in
  `--love` (rose, the only warm colour on the page); like = thumbs up;
  dislike = thumbs down; no sentiment = nothing. The glyph sits in the
  text run, sized to the x-height, not on the baseline.
- **Line 2**: title name (semibold), year beside it.
- **Line 3**: the review text when there is any, clamped at 4 lines.
- Poster on the left (gradient thumb; the size is yours).
- **Second person for own entries**: "You reviewed", "You want to watch"
  (never "wants"). Friends: "Cleo wants to watch", "Nick reviewed".
- **Toolbar**: shown only while the entry is hovered or holds the cursor,
  in a fixed seat so the entry's height never changes. A friend's entry:
  List (bookmark; "Listed" filled when on your list; "Tracking" as plain
  state above List) · Download (or plain state "Downloading" with a 3px
  hairline / "In library") · Ignore last. An own entry: the List and
  Download slots mean the same thing (the title's state in your ladder and
  library); Ignore's seat holds **Delete** (the modal's verb is "Delete
  review" / "Delete listing"; in the toolbar just "Delete").
- Whole-entry click opens the title modal (not shown). Names are not links.

## Own entries — how they read among friends'

The name is "You". Beyond the word, the direction decides whether an own
entry carries any visual mark, and must justify it in REASONING.md. Not
allowed: chips, badges, accent/edge bars (rejected as "LLM design"),
avatars, left/right alternation (chat bubbles). The one precedent is the
You card's primary-tinted border (`.own-border` in base.css); "You" set in
the primary colour is also acceptable; so is nothing at all.

## The scope control

Three options, Everyone / Friends / You. The house pick-one is the
segmented pill (`.seg` in base.css: glass rail, chosen option lifted on a
neutral fill). A direction may propose text tabs with the zone-tab
underline instead if it argues why. Placement is the direction's call.

## States to show — all on one page, each under a small `.sec` label

1. **Everyone** — the full list below, own entries interleaved. Then
   "Show older".
2. **Friends** — the same list with own entries gone (the first five are
   enough).
3. **You** — the four own entries.
4. **You, empty** — nothing shared yet. Headline: "What you review and list
   lands here". Body: "A review is always shared. A title you list is
   shared while Share your watchlist is on." One quiet action: "Settings →
   Social".
5. A friend's entry hovered (toolbar: List · Download · Ignore).
6. An own entry hovered (toolbar: Listed (filled) · In library · Delete).
7. The keyboard cursor on an entry (2px primary ring).

States 5–7 can be single entries under their labels, as round 2 did.

## Data — eleven entries, newest first

Per-title hue (`--h`) stays consistent: Sample Show 350, Movie A 200,
Show B 264, The Long Field 140, Harbor Lights 60.

1. Cleo wants to watch · Sample Show (2024) · 12m ago
2. You reviewed ♥ · Movie A (2026) · 1h ago · "Saw it twice. The last twenty minutes are the whole film."
3. Nick reviewed 👍 · Movie A (2026) · 2h ago · no text
4. Nick wants to watch · Movie A (2026) · 2h ago
5. Bob reviewed (no sentiment) · Show B (2021) · 1d ago · "Slow start, give it three episodes." · title In library
6. You want to watch · The Long Field (2025) · 3d ago
7. Sam wants to watch · The Long Field (2025) · 3d ago · title on your list (Listed)
8. You reviewed 👎 · Harbor Lights (2023) · 6d ago · "Not for me. The score does all the work the script should."
9. Cleo reviewed (no sentiment) · Show B (2021) · 1w ago · "Fine."
10. Bob wants to watch · Harbor Lights (2023) · 2w ago · title Downloading
11. Sam reviewed ♥ · Sample Show (2024) · 3w ago · "Every episode ends on the right beat."

Then "Show older".

## House rules

Dark slate, glass, system fonts, calm. Colour only for signal: the rose
heart, the primary ring and the pill's active fill. No chips, no accent
bars, no avatars, no day dividers, no group headers, no animations beyond
a 120ms opacity fade, no real titles. Posters are the `.thumb` gradient.
UIDR-038's anti-patterns stand: wall of watching, title-first row,
grouped rows, state as decoration, social-network chrome, hover jump, day
dividers. Inline SVG symbols for the bookmark, download arrow, thumbs and
heart (currentColor); no icon fonts, no external assets.

## Directions

- **1-time-rail** — one column, about 880px. A hairline rail runs down
  the left of the feed; every entry hangs from a marker on it, and the
  relative time moves out of line 1 onto the rail beside the marker, so
  the time axis is drawn rather than implied. Own entries' markers are
  filled primary, friends' hollow neutral — the marker is the only own
  mark. The entry itself keeps the poster-left glass card. The scope pill
  sits at the head of the rail on the tab strip's line. REASONING.md must
  argue why the rail is not "chrome" under UIDR-038.
- **2-poster-forward** — one column, about 1000px. The poster grows to
  96×144 and leads; the text block sits beside it vertically centred,
  sentence 15px, title 17px, review text 14.5px in a lighter tone. Cards
  with 16px radius, 20px padding, 12px gap. Own entries carry the You
  card's `.own-border`; nothing else. Scope pill right-aligned on the tab
  strip's line.
- **3-editorial-list** — one column, about 920px, no per-entry card.
  Entries are rows separated by hairlines (border at 8% alpha), poster
  56×84, sentence 15px, title 16px semibold, review text 14px at 70%. The
  relative time is right-aligned in its own column at 55% so the axis
  reads down the right edge. Own entries: "You" in the primary colour,
  nothing else. Scope as three text links with the zone-tab underline on
  the right of the same line as Feed / Watchlist / Friends (the secondary
  group lighter), argued in REASONING.md against the pill. Hover gives the
  row the 6.5% fill and the toolbar in its seat.

## Deliverable

`index.html` (linking `../base.css`) + `REASONING.md`: style, decisions,
requirements mapping, trade-offs, how it holds at 3 entries and at 300,
how own entries read among friends' without chrome, where the scope
control sits and why, and what width the Discovery page becomes.

## Outcome (2026-09-24)

`3-editorial-list` chosen, with two changes: the scope moves from text
tabs onto the segmented control at the right of the tab strip's line, and
the rows sit in one inset glass surface, the Watch History list's idiom.
`1-time-rail` rejected: the rail is chrome, the cards widen and empty, and
the page tabs had to move. `2-poster-forward` is the imagery-led
alternative, not taken: six rows per screen and an own mark that does not
read. Own rows carry no Delete on the toolbar after the coherence pass;
withdrawing stays in the modal. Design: `../2026-09-24-feed-timeline-scope-design.md`, UIDR-045.
