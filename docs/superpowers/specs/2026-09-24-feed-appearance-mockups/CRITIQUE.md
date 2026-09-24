# Round 4 critique — five directions for the Feed

Written 2026-09-24 after rendering every direction at 1920×1080 (top
and 2600px tall) and reading each REASONING.md. Same sixteen rows,
same artwork, same frame. The owner's asks, in order: tell authors
apart at a glance (own vs friend; one friend from another, at thirty);
make the page gorgeous — *holy crap*; and, as a note, leave a space
for a person's photo with a default when there is none. The diagnosis
they answer is in `../2026-09-24-feed-appearance-design.md`.

Two things about the setup that colour every judgement:

- **The mockups render at 1:1.** The app renders under the UI scale
  (screen ÷ 1920 × preference), so a 4K panel sees the 1920
  composition and a scaled-down preference shrinks all of it. Judge
  proportions, not absolute size.
- **Sixteen rows with three friends is the owner's real case.** Six
  authors appear in the window; one run of two exists. Devices that
  pay off only for a prolific friend or a roster of thirty are paying
  off in a future that has not arrived.

## How they were judged

| Criterion | What it asks |
|---|---|
| **Own at a glance** | Is an own row pre-attentive — a channel besides a hue on a small word? |
| **Friend from friend** | At six in the window; at thirty on the roster; with and without a photo |
| **Presence** | Does the page belong on the same monitor as Home? Does it pop on the first screen, and on every screen after? |
| **Still a feed** | Rows per fold; the time axis; scanning; what a new arrival does to the page |
| **Rule cost** | Which standing rules it bends or breaks, and whether the exception is one a record can state cleanly |
| **Cost and risk** | What the implementation needs beyond the row component; what could fail with real data |
| **Propagation** | The owner said this round sets a direction for the app. What does the direction give the other surfaces? |

## 1 · Cinematic rows

**What it does.** Full-width bands, 152px, each carrying its title's
backdrop from x=560 to the right edge under a left-weighted scrim in
the base hue; the identity tile, a 72×108 poster and the text in the
dark zone; the time over the picture at the far right. Own = a filled
primary tile; "You" set like any name.

**What works.** This is the only direction that pops on *every*
screen. Scroll anywhere and the page is a column of captioned stills
with a fixed spine on the left (tile, poster, sentence at the same x
on every band) — the shape a streaming service's activity page has,
in this app's own materials (base-hue scrim, `text-on-image`, the
Friends tab's monogram). The own mark is the filled disc: a shape and
fill change, found without reading, and the second person confirms.
The poster beside the still means recognition never depends on the
crop. The tile's photo state is a real portrait crop and reads as a
person at 40px.

**What fails or worries.**

- **The crop is the whole risk.** A 152px band shows a 21% slice of a
  16:9 still at 1920; the designer hand-set thirteen `object-position`
  values and still calls Nosferatu the failure case (a colour field).
  The app has no focal-point data. This must be measured on the
  owner's real library before the direction is chosen (see the
  recommendation): render thirty real backdrops at the slice with one
  fixed position and count how many land on nothing.
- **Adjacent rows of one title repeat the still** (Charade twice,
  Big Buck Bunny twice). Real behaviour, reads like a bug.
- **The time is 1,700px from the words** at full width. The designer
  calls it an orientation, not a read; I would rather see it tried at
  the text zone's edge.
- **Two lines of review text.** The words are the Feed's human
  content and a 152px band holds two lines at 58ch. The owner's real
  reviews are one-liners today; a long one is cut.
- **Six and a half bands per fold** against nine shipped rows.
- **Bandwidth.** One backdrop per row at `?w=1280`, about 150KB
  each: 2.4MB for a page of sixteen. Fine on a LAN desktop app that
  already trades bandwidth for perception (UIDR-012); needs the
  backdrop tier warmed for unowned titles.

**Rule cost.** UIDR-045 rule 3 replaced (the tile is the own mark);
rule 5 broken (no shared surface, no hairlines — "a hairline between
two pictures is a third picture", which is right); UIDR-038's *social
network chrome* bent for the tile, *wall of watching* bent because
the page is two-thirds picture; UIDR-033 kept in substance (each
band's artwork is its own subject). Each exception is stateable in
one sentence.

**Cost.** A backdrop resolver alongside the poster ladder
(`ActivityPosters` → library backdrop, referenced tier, hotlink),
backdrop warming in `TmdbArtwork`, `backdrop_url` on `FeedEntry`, an
`IdentityTile` component shared with `PersonCard`, the band's scrim
recipe as CSS, the Discovery page's full-width opt-out, and the
Watchlist and Friends tabs reflowed at the new width. Medium.

**Propagation.** High. The band is a reusable row idiom: the
Watchlist's rows, the Friends card's shelves, History's rows and
Incoming's activity could all take "a still under the house scrim
with a dark text zone". The identity tile becomes the app's person
device everywhere a person is named.

## 2 · Poster gallery

**What it does.** Full width, a lattice of glass cards
(`minmax(560px,1fr)`: three at 1920), each 208px with a 120×180
poster, the name as a 16px semibold byline in a per-friend hue, the
time at the card's foot. Own = You in the primary plus a 40% primary
border.

**What works.** It fills 1920 and looks like a product: twelve
actions per fold, big posters with real shadows, one card height so
the lattice never goes ragged. The typographic hierarchy (coloured
name, white title) is the clearest of the five at reading distance.

**What fails.**

- **The hue is a chip palette by another route.** Six pastels on one
  screen — orange, teal, amber, purple, green, pink — on the names.
  The designer's argument (text only, fixed lightness and chroma) is
  honest, and the page still reads as coloured-by-person, which is
  the thing the house colour rule and the owner's standing objection
  exclude. At thirty the hue does not even name a person; the
  designer says so.
- **The own mark is the weakest of the five.** A 40% primary border
  on glass is invisible at a glance; You in the primary is the mark
  the diagnosis called too quiet. The direction's device is for
  friends, and own rows got the leftover.
- **The time axis is gone.** Time reads left-to-right within a row,
  then down; the times are 13px at the card feet. A reader has to
  learn that a row is a time band.
- **Listing cards are two lines beside a 180px poster** — mostly
  air; and adjacent duplicates (two Charade, two Pioneer One) sit
  side by side.
- Sixteen `backdrop-filter` layers on one page.

**Rule cost.** Colour-is-signal bent on the one point the owner has
held every time; UIDR-045 rule 3 bent; the time column re-seated;
*wall of watching* in shape. The colour cost alone is disqualifying
unless the owner has changed their mind about per-person hue.

**Propagation.** The lattice could serve the Watchlist; the hue
device would not travel.

## 3 · Author runs

**What it does.** Adjacent rows by one author fold into a run: a
heading (40px tile, 17px name, the run's newest time) over a strip of
96×144 poster cards three across; own runs on an 8% primary tint with
a filled tile; "You" neutral; a run breaks after 24 hours.

**What works.** The strongest own mark of the round — tile fill plus
a tinted band, found from across the room — and the largest, most
consistently placed name (17px semibold at the head of every run).
Nick's run of two reads exactly as intended: one person, two posters.

**What fails.**

- **Fifteen of sixteen rows are runs of one.** The device pays only
  when one person acts several times in a row; with three friends
  interleaving, the page is a stack of heading-plus-one-card bands
  with the right two-thirds empty. About four and a half runs per
  fold. At thirty friends interleaving is heavier and runs rarer.
- **No dominant element and no artwork beyond the poster.** Bigger
  posters in a 1280 column, the right third of the screen still empty.
  It does not pop.
- **An action inside a run loses its own time**, so the designer had
  to invent a 24-hour rule to keep the You scope honest, and calls
  that rule the thing they are least sure of. Runs are unstable at
  their edges (a new action can merge into run 1 and shift its cards;
  hiding own rows under Friends fuses two friend runs).
- **A horizontal axis enters the nav graph** (cards along a strip
  before down).

**Rule cost.** The highest: UIDR-038 rule 2 bent, rule 3 bent, its
*grouped rows* anti-pattern re-argued, UIDR-045 rule 3 broken twice,
rule 5 bent. Each argument is careful; there are too many of them for
a payoff that arrives only with a prolific friend.

**Propagation.** Low. The run rule survives in a cheaper form in
direction 5 (a tile drawn once per run, rows unchanged).

## 4 · Front page

**What it does.** A size ramp by recency inside the 1280 container:
the newest action as a 1280×300 lead (backdrop under the house scrim,
147×220 poster, 32px title, 48px tile), the next three as 416×176
backdrop cards, the rest as the shipped list with a 32px tile and a
64×96 poster. Own = filled tile; "You" neutral.

**What works.** The best single object of the round. The lead is a
front page: a still, a headline at 32px, a sentence, a poster, a
person — the Home principle (one dominant element per screen) brought
to the Feed. The ramp is honest about order: size is a function of
position only; nothing is promoted for having words. Fixed box
heights mean a new arrival re-projects the ramp without moving
anything below it. The identity tile at three sizes stays one thing.

**What fails or worries.**

- **The pop is one screen deep.** From the fifth action on, it is
  the shipped list with a tile — the designer's own trade-off. Home
  works this way too (hero, then rails), but Home's rails are
  artwork; this list is not.
- **Two languages on one page**: backdrop units above, a plain list
  below. Direction 1 is one language at one size; this is two.
- **The lead swaps wholesale on every new action.** Boxes do not
  move, but the page's hero changes with each arrival; on an active
  roster the top is never the same twice. Acceptable for a feed;
  worth seeing live.
- **Adjacent duplicates on the cards** (Charade twice, side by side,
  same still) and 13px review text on cards.
- **The crop risk, at 4.3:1**, same as direction 1 and larger on the
  lead. Hand-set focal points; the app has none.
- **The right 540px at 1920 is empty**; the lead stops at the
  container's edge.

**Rule cost.** Moderate: UIDR-045 rule 3 bent (tile for word),
*title-first* bent on the lead only, the 120ms ceiling read as a
duration rather than one element, the poster one size up. UIDR-038
rule 2 kept outright.

**Propagation.** High. The ramp (lead, cards, list) is a pattern for
any surface with a "newest": Incoming's activity, History.

## 5 · Tile column

**What it does.** The shipped list with three changes: a 56px tile
column where the monogram is drawn on the first row of an author's
adjacent run and left empty after it; the poster at 80×120; the
title's backdrop as a soft blurred glow behind the poster. Type one
step up. Own = filled tile plus You in the primary.

**What works.** The cheapest and the least risky; every rule but two
kept; the run rule costs nothing (a property of adjacent rows) and
gives the chat-client rhythm. The own mark is two channels (a solid
disc, the blue word). The glow is a genuinely nice idea: the
artwork's own colour, never a band, never state.

**What fails.**

- **Better, not gorgeous.** It is the shipped page with a tile and a
  glow, still a 1280 column with the right third empty, still one
  tone with a warm smudge behind some posters. The glow is only as
  strong as the artwork (bright behind Big Buck Bunny, gone behind
  Nosferatu). It does not meet the owner's bar.
- **The You scope is one tile then empty cells** — the designer's
  own worry.
- **Six and a half rows per fold** for a page that gained little
  presence for the height.

**Rule cost.** Lowest: UIDR-045 rule 3 bent (one marker in its own
column), UIDR-038 chrome bent for the tile.

**Propagation.** Low; the tile column is the Feed's alone. The tile
itself propagates in every direction.

## Side by side

| | 1 Cinematic rows | 2 Poster gallery | 3 Author runs | 4 Front page | 5 Tile column |
|---|---|---|---|---|---|
| Own at a glance | filled tile — strong | word + faint border — weak | tile + tint — strongest | filled tile — strong | tile + word — strong |
| Friend from friend (6 / 30) | letter + name / photo | hue — strong / does not name | 17px name + letter | letter + name / photo | letter + name / photo |
| Presence, first screen | strong | strong | middling | strongest | modest |
| Presence, every screen | strongest | strong | middling | list after the ramp | modest |
| Rows per fold | 6.5 | 12 (three across) | ~4.5 runs | lead + 3 + ~4 | 6.5 |
| Time axis | far right edge | lost | per run only | right, per tier | right column |
| Rule cost | moderate, stateable | colour rule — disqualifying | highest | moderate | lowest |
| Data risk | crop on 21% slice | none | 24h rule, unstable runs | crop on the lead | none |
| Implementation | backdrops + tile + full width | lattice + hue | runs + strips + nav | backdrops + tile + 3 tiers | tile + glow |
| Propagation | high (the band) | low | low | high (the ramp) | low |

## Recommendation

**Cross directions 1 and 4: cinematic bands as the page, with a lead
for the newest action.** One visual language — a still under the
house scrim, a dark text zone, the identity tile, the poster — at two
sizes: a 300px lead for the newest action, then 152px bands. It keeps
what each does best (4's dominant first screen; 1's pop on every
screen after) and drops what each does worst (4's fall-off into the
plain list; 1's uniform column with nothing leading it). It is still
flat: size is position, nothing else. It is one row component with a
size property, not two components.

Before that round, **measure the crop risk on real data**: pull
thirty backdrops from the owner's library, render them at the 21%
slice with one fixed focal position (start at 35%) and at the lead's
4.3:1, and count how many land on nothing. If more than a handful
fail, the band needs a taller box or a smaller slice before it is
chosen — and that changes the design, so it is a round-5 input, not
an implementation detail.

Round 5 also settles, by rendering rather than argument:

1. **Full width or 1280.** Direction 1 took full width (a 21% slice,
   presence); direction 4 kept 1280 (a 37% slice at the band, the
   house container). Render the cross both ways at the owner's real
   UI scale.
2. **The time's seat.** At the text zone's right edge (x≈560) against
   the band's far right. The far right is 1,700px from the words.
3. **Adjacent duplicates.** Offset the crop per row (a few percent)
   or accept the repeat.
4. **Review text.** Two lines at 152px, or a taller band for reviews
   with words (a variable band height is not a hover jump; the height
   is fixed per row at render).
5. **"You" neutral or primary** beside a filled tile. Three designers
   set it neutral; one kept the primary. With a filled tile, neutral
   is one mark instead of two; recommend neutral.
6. **The own tile's fill.** Direction 1 used the button primary (62%)
   with a white initial for contrast; 4 and 5 used the text primary.
   One value, in the tile component.

**Not recommended.** Direction 2, on the colour rule alone — the hue
is the direction, and it is the one device the owner has excluded
every time. Direction 3, because its device pays only for a prolific
friend and costs the most rules. Direction 5, because it is the
shipped page improved, and the owner asked for more than improved;
its run rule and glow are worth remembering if the cross fails the
crop test.

**Records the cross would amend.** UIDR-045 rule 3 (the identity
tile is the own mark) and rule 5 (bands, not one surface); UIDR-038's
*social-network chrome* (the identity tile is the app's person
device, photo or monogram) and *wall of watching* (a captioned still
per action is not a wall of titles); UIDR-033 (a row's own title
artwork is that row's subject). A new UIDR for the band and the
identity tile, with every size named, comes out of round 5.
