# 2 · Poster-forward — reasoning

## Style

One column, 1000px. Each entry is a glass card exactly the height of its
poster: a 96×144 gradient thumb on the left, and beside it a text block
centred on the poster's height. The three lines are round 2's, one size
up: the sentence at 15px (name at 92%, verb at 75%, time at 55%), the
title at 17px semibold with the year at 13px/55%, the review at 14.5px/70%
clamped at four lines. Cards have a 16px radius and 20px padding and sit
12px apart. The page is dark slate with the shared glass; the only colour
is the rose heart, the primary cursor ring, the pill's lifted option, and
the primary tint on an own entry's border.

The look is a library shelf rather than a message log: every card is the
same height, the posters form a straight column down the left, and the
text reads off each poster the way a spine label reads off a box.

## Decisions

**A card is the poster's height, always.** `.body` has `min-height:144px`,
so a listing (two lines) and a review (three lines) produce the same
184px card. Uniform height is what makes the poster column read as a
column; it also means the feed's vertical rhythm is fixed at 196px per
entry regardless of content, so scanning is predictable.

**Two 20px seats, one for the toolbar, one to balance it.** The toolbar
keeps round 2's fixed 20px seat at the foot of the text block. A seat at
the foot alone would centre the text in the 124px above it, 10px high of
the poster's centre. `.body` therefore carries `padding-top:20px` as a
matching seat at the head, and `.text{margin:auto 0}` centres the lines in
the 104px between them — the text's centre lands on the poster's centre
(verified: entry 1's text block spans 251–299 against a poster centred at
276). A four-line review is 22+24+6+87 = 139px, taller than 104, so the
card grows by the overflow; the toolbar is in flow below the text and can
never overlap it. Hover changes opacity only; no height ever moves.

**Sentiment glyph in the text run.** Filled SVG symbols (heart, thumbs up,
thumbs down) at 0.78em with `vertical-align:middle`, which centres the
glyph on the x-height — the same mechanism the shipped
`Sentiment.sentiment_glyph` uses after commit 80d46627. Filled rather than
stroked because a 2px stroke in a 24-unit viewbox turns to mush at 11px.
The heart is `var(--love)`; the thumbs are `currentColor` at the
sentence's tone, so the only warm colour on the page is love.

**Toolbar icons are stroked, glyphs are filled.** The bookmark and download
arrow at 15px have room for a 2px stroke and read lighter that way; the
filled bookmark is the Listed state, which is the one place fill carries
meaning in the toolbar.

**Per-title state is consistent across entries.** Show B is In library on
both Bob's and Cleo's entries; Harbor Lights is Downloading on Bob's entry
and on your own review of it; The Long Field is Listed on Sam's entry and
on your own listing (which is Listed by definition). The state-6 specimen
carries Listed · In library because the brief asks for exactly that
toolbar; it is illustrative of the own toolbar's three slots, not a claim
about Movie A's state in the Everyone list (where Movie A has no state and
its three entries all show List · Download).

**Empty state as a card.** The You-empty state is a glass card at the
column's width with the headline at 17px semibold, the body at 14.5px/70%
and one ghost button, "Settings → Social". A card, not loose text, so the
column keeps its shape when there is nothing in it.

## Requirements mapping

| Brief item | How it is met |
|---|---|
| One column, about 1000px | `.page{max-width:1000px}` in the style block; the shared `.page` is 768 |
| Poster 96×144, leads | `.entry .thumb{width:96px;height:144px;border-radius:8px}` first in the flex row |
| Text block beside it, vertically centred | `.body` flex column, `min-height:144px`, symmetric 20px seats, `.text{margin:auto 0}` |
| Sentence 15px | `.l1{font-size:15px}` |
| Title 17px semibold | `.l2{font-size:17px}`, `.l2 b{font-weight:600}` |
| Review 14.5px, lighter tone | `.l3{font-size:14.5px;color:…/.7}` clamped at 4 lines |
| Cards 16px radius, 20px padding, 12px gap | `.entry{border-radius:16px;padding:20px}`, `.feed{gap:12px}` |
| Own entries carry `.own-border`, nothing else | `class="entry glass own-border"` on entries 2, 6, 8; "You" set in the ordinary name tone |
| Scope pill right-aligned on the tab strip's line | `.strip` is `space-between`; tabs left, `.seg` right, one 36px row; tab padding set to 8px so the underline and the pill's bottom edge share a line |
| Line 1: name (medium), verb, glyph, separator, time | `.who` 500 weight; `<svg class="g">` after the verb; `·` at 40%; time at 55% |
| Line 2: title semibold, year beside | `.l2` baseline-aligned flex |
| Line 3: review clamped at 4 lines | `-webkit-line-clamp:4` |
| Second person on own entries | "You reviewed", "You want to watch" |
| Toolbar in a fixed seat, hover only | `.bar{height:20px;opacity:0;transition:opacity .12s}`; shown on `:hover`, `.hovered`, `.cursor`, `:focus-within` |
| Friend toolbar: List · Download · Ignore, Ignore last | `.v.end{margin-left:auto}` on Ignore |
| Own toolbar: Listed (filled) · In library · Delete | `#i-bm-on` + `.v.on`; `.st` plain state; Delete in Ignore's seat, pushed right |
| Plain states: Listed, In library, Downloading with 3px hairline | Entries 7, 5/9, 10/8; `.st .w.prog:after` hairline at `--pct` |
| Keyboard cursor: 2px primary ring | `.entry.cursor{outline:2px solid var(--p);outline-offset:-1px}` |
| Tab count follows the scope | Feed 11 / 8 / 3 / 0 across states 1–4 |
| State 1 Everyone, 11 entries, Show older | Full list in the brief's order, then `.btn.ghost` centred |
| State 2 Friends, first five | Entries 1, 3, 4, 5, 7 |
| State 3 You | Entries 2, 6, 8 — see the note on the brief's data below |
| State 4 You, empty | Headline, body and "Settings → Social" as written in the brief |
| States 5–7 as single entries | Sam ♥ hovered; You ♥ own-bordered hovered; Cleo with the cursor |
| Hue per title | 350 / 200 / 264 / 140 / 60 via `--h` |
| Inline SVG symbols, no icon fonts, no external assets | One `<defs>` block; `<use href>` throughout |
| No chips, badges, bars, avatars, dividers, headers, alternation | None present; own entries differ by border colour only |
| 120ms opacity transitions only | `.bar` and `.entry` background use `.12s`; nothing else animates |
| No text below 55% alpha | Year, time, tab counts, `.sec` at 55%; only `·` and icons below |
| System fonts, dark slate, no light theme | Inherited from `base.css` |

## Trade-offs

- **Height per entry.** 196px per entry (184 card + 12 gap) against round
  2's ~104px. Half the entries per screen; see the next section.
- **Air in listings.** A listing has 47px of text inside a 104px text
  region, so there is roughly 28px of empty card above and below the text.
  That air is the price of vertical centring and uniform height. It is
  not dead: it is what makes a listing and a review sit at the same
  weight, and the toolbar lands in it on hover.
- **The head seat is invisible.** Nobody sees the 20px above the text; it
  exists so the geometry is right. A reviewer looking at the CSS could
  read it as waste. The alternative — centring in the 124px above the
  toolbar seat — puts the text 10px above the poster's centre on every
  card, which the eye reads as "slightly too high" without knowing why.
- **A four-line review breaks uniform height.** Rare in practice (the
  brief's longest review is one line at this width), and when it happens
  the card grows by at most 35px. Accepted over clamping at three lines.
- **Filled thumbs.** Fill is the only way the thumbs survive 11px. It
  makes them a touch heavier than a stroked heroicon would be in the
  shipped app; a filled heroicon (`hero-hand-thumb-up-solid`) is the
  matching choice there.

## At 3 entries and at 300

**Three entries** fill 588px under the header — about 70% of a 1080px
viewport. The column looks populated, not sparse: three 184px cards with
three posters make a shelf, where round 2's three rows at 48×72 made a
strip. This is the direction's strongest case.

**Three hundred entries** is 58,800px, about 54 screens. Per screen you
get 4.7 entries on the first (under the header) and 5.5 thereafter, against
round 2's ~9–10. That is a cost, and it is real: someone catching up on a
week of an active circle scrolls twice as far. Three things offset it
without removing it:

1. The scope control. Friends removes your own entries, You removes
   everyone else's; a long feed is usually being read for one of the two.
2. "Show older" already paginates the feed; the first page is bounded.
3. Scan speed per entry is higher, not lower — the poster is recognisable
   at 96×144 where a 48×72 thumb needs the title read beside it — so the
   time to find an entry does not scale with the pixels scrolled.

If the cost proves too high in use, the honest adjustment is 80×120 (card
160px, ~6.5 per screen), not a denser anatomy; the direction does not
survive going back to a thumbnail.

## Own entries among friends' — the border alone

An own entry is the same card with `border-color: primary/0.3` instead of
neutral/0.09. At rest, against the glass, that is a faint blue edge —
visible when you look for it and invisible when you are reading. This is
deliberate: the feed is meant to read as one timeline of one kind of
thing, and the brief's rule that "You" is an author like any other means
an own entry should not announce itself. The word "You" at the head of the
sentence is the first thing the eye reads on every entry anyway; the
border is a confirmation for the peripheral glance, not the primary
signal.

In the Everyone state the three own entries (2, 6, 8) are interleaved by
time and the border marks them faintly; in the You state every card
carries it and it reads as the scope's tint rather than a per-card mark.
That the same mark works at both densities is the argument for a border
over a coloured name: a column of primary "You"s would shout, a column of
tinted borders does not. Nothing else — no fill change, no glyph, no
position change.

## The scope control

The pill sits on the tab strip's line, right-aligned, with Feed /
Watchlist / Friends on the left. Reasons:

- The tab strip is where the page already answers "which view"; the scope
  is a second axis of the same question (which view, whose entries) and
  belongs on the same line, not above the feed as a second toolbar.
- Right-aligning keeps the tabs' left edge fixed across the three tabs —
  the pill only appears on Feed, and the Watchlist and Friends strips
  should not shift when it goes.
- The pill and the tabs are both 36px tall, so the tab underline and the
  pill's bottom edge share a baseline; the row reads as one line, not a
  stack.
- The house pick-one is the pill; text tabs with the underline would
  compete with the real tabs to their left.

At 1000px the gap between "Friends 4" and "Everyone" is roughly 460px,
which is enough that the two groups read as separate controls without a
divider.

## Page width: 1000px

The Discovery page becomes a 1000px column (`max-w-[1000px]` in place of
`max-w-3xl`). Effects on the other two tabs, which share the column:

- **Watchlist** is a list of title rows (`space-y-2`, a small poster and
  text). At 1000px each row gains 232px of width that its text does not
  need, so a row reads as a short line on a long card — the same "strip on
  an empty page" problem this round is fixing for the feed, in miniature.
  The consistent fix is to give the watchlist row this direction's
  anatomy (a larger poster, the row at the poster's height); that is a
  follow-up, not part of this mockup.
- **Friends** person cards have a six-across watched strip whose cell is
  fluid. At 768 a cell is ~116px wide; at 1000 it is ~155px (232px tall).
  The strip fetches a 240px derivative, which still covers a 1× panel but
  goes soft at 2× (310 device px); moving to 320 keeps it crisp. The cards
  otherwise gain air, which the person card's headline-plus-strip layout
  absorbs well.

The width was chosen for the feed: with 20px padding and a 20px gap the
text block is 812px, which sets a one-line review at 14.5px to about 110
characters — long enough that the brief's reviews stay on one line and a
real paragraph clamps at four without turning into a wall. 920 would have
worked; 1100 pushes the pill too far from the tabs for one row to hold.

## Note on the brief's data

The brief's state 3 says "the four own entries" but its data has three
(entries 2, 6, 8). The mockup shows the three that exist and counts
Feed 3; the state label says so.
