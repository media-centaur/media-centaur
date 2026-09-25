# Round 8 brief — the assembled couch page (2026-09-25)

Round 7 (`BRIEF-7.md`, `CRITIQUE-7.md`) re-scaled the cinematic feed to
couch floors and rendered the owner's Friends rail. The owner's review
of it, in five points, is what this round builds:

1. **The masthead was busy** and pushed the rail into an awkward
   secondary place. Gone. The page is **two full-height columns** from
   the tab strip down: the feed column on the left, the Friends rail on
   the right. The primary state has **no lead** — every band is already
   a photograph at couch scale, and the newest is first. R1's taller
   first band is rendered once as the alternative state.
2. **A friend may withhold data.** `share_watched` and `share_watchlist`
   are both **off by default**; only reviews always publish. So most
   friends share reviews only. Every person surface designs for four
   sharing states (below); none is a fallback.
3. **Looking at a friend is for the few things they last watched**,
   which never reach the Feed. The rail's rows are compact **person
   cards** with a Recently watched strip when the person shares
   watches — not presence lines.
4. **Many friends.** The rail shows the most recently active friends up
   to a cap of eight, You first, with **All N friends** at its foot;
   the rail scrolls with the page (one scroll region, for the gamepad).
5. **Paging is deliberate**: a window of twenty bands; **Show older** at
   the column's foot appends twenty, up to sixty in the DOM, then ends;
   new arrivals prepend live only when the page is at the top, otherwise
   they queue behind a quiet **"3 new"** control at the column's head.

And one decision from the owner's question: **the Friends tab stays, at
every width**, as the full page where the roster is managed. The tab
strip is constant — Feed · Watchlist · Friends — the rail is a summary
that opens the tab (its cards, "All N friends" and "Manage friends" all
go there; a card goes there scrolled to its person); the rail hides on
the Friends tab itself; below the fold width (1700) the rail folds away
and nothing else changes shape.

## Couch floors

As `BRIEF-7.md`: read text ≥ 22px, secondary ≥ 18px, band title ≥ 28px,
tiles 56 on a band / 48 on a card, posters ≥ 96×144 on a band, 32px
targets, a 3–4px cursor ring, text over imagery ≥ 4.5:1, the half-size
check on every render. The crop rule from `MEASUREMENT.md`
(`50% 30%`, `50% 38%` on the second of two adjacent units of one title,
no per-title positions).

## The band (from R1, re-checked)

The feed column is about 1236px at 1920 (rail 560, gutter 24). Band
224px: tile 56 at the left, poster 100×150, the text zone to x≈700
(sentence 22, title 28, review 22 at two lines, year and time 18, the
time right-aligned at the text zone's edge), the seat 32px on the
poster's foot (18px verbs, 20px icons), the image box from the text
zone's edge to the band's right edge (about 536px, a 74% slice) under
the base-hue scrim with a 360px dissolve. Own = the filled button-primary
tile with a white initial; "You" neutral. Toolbar contract unchanged.

## The person card — one anatomy, two sizes

The rail card and the Friends tab card are **one component at two
widths** (560 in the rail; the tab's column width on the Friends page).
Anatomy, top to bottom:

- **Head**: the identity tile (48 in the rail, 56 on the tab), the name
  (22px semibold), the time of the latest act (18px) at the right.
- **Presence line** (20px): the latest act of any kind in the Friends
  card's vocabulary — "reviewed Charade ♥", "wants to watch Sintel",
  "watched S01E03 of Pioneer One" — this is the one definition of
  presence, for the rail and the tab alike.
- **Recently watched strip**: three posters at 64×96 in the rail (up to
  five at 96×144 on the tab, with the "all N" tile as today), **only
  when the person shares watches**.
- **Sharing states**, each drawn: (a) *shares watches* — the strip and
  the line; (b) *reviews only*, the default — the line, no strip, and a
  quiet 18px note "Doesn't share watching" so the absence reads as their
  choice; (c) *shares listings but not watches* — as (b), the line may be
  a listing; (d) *nothing shared yet* — the line says so, nothing else.
  Plus a photo tile on one friend and the monogram on the rest.
- **You first**, the own tile, the subtitle "How friends see you" (18px),
  your own sharing state mirrored (draw You as reviews-only, the
  default, with the note reading "You don't share watching").
- On the Friends tab only: the Wants to watch and Reviewed text rows as
  today, the key as a footer fact, Remove friend, and Add a friend as a
  card at the page's foot. In the rail: none of these; the card is a
  nav item that opens the tab.

Rail order: You, then friends by latest activity; a cap of eight, then
**All N friends** (a link, 20px) at the foot. On the Friends tab: every
person, the same order, then Add a friend.

## Paging, drawn

- The feed's first window is twenty bands; the page shows the column's
  foot with **Show older** (a 32px ghost control on the reading edge,
  20px). After the third Show older (sixty bands) the foot reads "That's
  the last two months" or the honest equivalent — say what it reads.
- **"3 new"** at the column's head: a 32px control on the reading edge,
  20px, drawn as a state with the page scrolled into the column (the
  strip out of view, the control at the column's top edge). Pressing it
  prepends and scrolls to the top; at the top, arrivals prepend live and
  the control never shows.
- Scope changes and Show older never touch the rail.

## Two pages

- **`G-couch-feed`** — the Feed and Watchlist tabs beside the rail,
  states: (1) Everyone, no lead, twenty bands then Show older; (1b) the
  first band as R1's taller lead, one strip of four; (2) Friends scope;
  (3) You scope; (4) You, empty (the rail still present); (5) a friend's
  band under the cursor with the seat shown (the TV's hover); (6) an own
  band under the cursor; (7) the photo tile on a band; (8) a band with
  no artwork; (9) two adjacent bands of one title; (10) the rail's four
  sharing states and You, all visible in one strip of the page; (11)
  "3 new" at the column's head; (12) the column's foot after the cap;
  (13) the Watchlist tab beside the rail (eight titles in P's anatomy at
  couch scale, the mast at the band's right edge); (14) the 1280 state,
  three tabs, no rail.
- **`G-friends-page`** — the Friends tab at couch scale: the tab strip
  (Friends active), no rail; the You card; four friends showing the
  four sharing states, one with a photo; the Wants to watch and Reviewed
  rows; the footer facts and Remove friend; Add a friend at the foot;
  the same page at 1280; and one state showing where a rail card lands
  (the page scrolled to Nick's card, his card under the cursor ring).

Both pages read the same anatomy above; where a size is not given, the
two designers choose it and name it, and G-friends-page's REASONING
lists every value it shares with the rail so the component is one.

## Deliverable

`<dir>/index.html` linking `../base.css` and `../art/`, `<dir>/REASONING.md`
(under 1500 words) opening with the size table for the spec, then the
sharing states, the paging rules as drawn, the fold, the 10-foot check's
findings, the rules touched (UIDR-038 rules 7–10, *wall of watching*,
UIDR-045, UIDR-033) with each exception, and the one thing you are least
sure of. Render with `page-shot` to the scratch folder at 1920 (three
passes), the half-size check, and 1280; nothing outside your folder; no
git, no mix.
