# Round 5 brief — the cinematic feed: bands with a lead (2026-09-24, night)

Round 4 produced five directions (`BRIEF.md`) and `CRITIQUE.md` chose
to cross two of them: **`1-cinematic-rows`** (every action a band that
carries its title's backdrop under the house scrim; the identity tile
as the author mark) and **`4-front-page`** (the newest action as a lead
card, a size ramp by recency). Read both `index.html` files and both
`REASONING.md` files first; you inherit direction 1's band and
direction 4's lead, and you are building one language at two sizes.
Read `MEASUREMENT.md` for the one crop rule you must obey, and
`DESIGNER.md` for how you work. The owner is asleep; nobody answers
questions — decide, build, and write the decision down.

## What the cross is

- **Flat, newest first, one entry per action** (UIDR-038 rule 2). Size
  is a function of position: index 0 in the scoped window is the
  **lead**; every other row is a **band**. No cards tier: two sizes,
  not three.
- **One anatomy.** Lead and band are one markup with a size property.
  Left to right on both: the identity tile, the poster, the text block
  (sentence · title and year · review text), the toolbar seat at the
  text block's foot; the time in its seat; the backdrop under the
  scrim to the right.
- **The identity tile is the author mark.** Monogram for a friend
  (`.mono`), a circular photo when one exists, and for You a tile
  filled with the button primary `oklch(62% 0.16 264)` carrying a
  white initial. **"You" is set like any name** (neutral, medium
  weight) — the tile is the mark, the second person is the grammar.
  Own with a photo: the photo inside a 2px primary ring.
- **The crop rule** (`MEASUREMENT.md`): every backdrop is
  `object-fit: cover; object-position: 50% 30%`. **No per-title
  positions.** When two adjacent rows show one title, the second uses
  `50% 38%`.
- **The scrim** is direction 1's recipe: the base hue, pixel-anchored
  stops, heavy under the text zone, clear on the right; hover
  multiplies the scrim's alphas by .8 and lifts the band's ground a
  step; nothing else moves. The lead's scrim is direction 4's two-layer
  recipe (to the right and to the top) in the same base hue.
- **The toolbar contract is unchanged**: a fixed seat, the row's
  height constant at rest and hovered, List · Download · Ignore on a
  friend's row, List · Download on an own row, no Delete.
- **Everything else** — the scope pill, the tab strip, the entry rule,
  the glyphs, the empty states, the modal — as shipped and as round 4's
  brief states them.

## The four directions of this round

Each is the same cross at one setting of the questions the critique
left open, so the owner compares settings on identical rows. Commit to
yours; note in REASONING what you would change if you had the others'
setting.

- **`A-cross-full`** — full width (`.content{max-width:none}`). Lead
  1820×340 (a 6:1 lead was called a sliver; 340 tall gives a 33% slice
  of the still). Bands 152px with the image box from x=560 (a 21%
  slice). Time at the band's far right, over the vignette, as direction
  1 had it; on the lead, top right.
- **`B-cross-1280`** — inside the 1280 container, left-aligned, as the
  app draws every container page. Lead 1280×300. Bands 152px with the
  image box from x=560 (a 720px box, a 37% slice). **Time at the text
  zone's right edge** (about x=540, on line 1's height, before the
  picture begins) — the critique's alternative seat — so the owner sees
  it against A's far-right seat.
- **`C-cross-capped`** — full-width page, but the band's image box is
  capped at 900px and right-aligned in the band, with ink between the
  text zone and the picture's dissolved left edge (a 30% slice,
  measured safe). Lead as A. This is the setting that keeps A's
  presence with B's crop safety; say honestly whether the ink gap reads
  as composed or as a hole. Time at the text zone's edge, as B.
- **`D-cross-words`** — as A, with one change: a band whose review has
  words grows to hold them — 200px with three lines at 15px and a 62ch
  measure — while a listing or a bare review stays 152px. Variable
  height is set at render, never on hover. Say what the two heights do
  to the column's rhythm and to the time axis. Time as A.

Every direction also shows, as extra labelled states after the brief's
nine: **(10)** the lead when the newest action is a review with words
(the You scope's lead is one; show it under Everyone too by putting a
review first in a second Everyone strip of four rows); **(11)** the
lead with no artwork; **(12)** two adjacent bands of one title with the
8% offset (rows 2–3, Charade); **(13)** a band hovered showing the
scrim step and the seat.

## Data

Round 4's sixteen rows (`BRIEF.md`, Data), same art in `art/`, same
authors, same title states, same counts (Feed 16 · Friends 11 · You
5, the Friends tab reads 30). Under Everyone the lead is row 1 (Cleo ·
Sintel, a listing); under Friends it is the same; under You it is row
2 (You · Charade, a review with words). Nothing else changes with the
scope.

## Deliverable

`<dir>/index.html` linking `../base.css` and `../art/`, and
`<dir>/REASONING.md` with: the sizes, alphas and gaps table; every
decision; the requirements mapping over states 1–13; the width and
what the Watchlist and Friends tabs do at it; the time seat argued;
what a new arrival does to the page (the lead swaps; say what moves);
how it holds at 3 and at 300; 1280 and 2560; the standing rules kept,
bent or broken with each exception stated; trade-offs; the one thing
you are least sure of. Render with `page-shot` to the scratch folder,
at least three passes at 1920×1080, once each at 1280×800 and
2560×1440; nothing outside your folder; no git, no mix.
