# Round 8 critique — the assembled couch page

2026-09-25. Two pages, both rendered at 1920, at half size and at
1280: `G-couch-feed` (the Feed and Watchlist beside the Friends rail)
and `G-friends-page` (the Friends tab). Both were built from one
written person-card anatomy in `BRIEF-8.md`; the point of this round
was to answer the owner's five notes on round 7 and to see whether the
two surfaces are one component.

## The Feed page

**This is the page.** Two full-height columns from the strip down —
the feed at 1236px, the rail at 560px — with no lead. The spatial
problem the masthead had is gone: left is the timeline, right is
people, and both start on the same line. At couch scale the bands
(224px, a 74% slice) are photographs and the newest is first, so the
page has no need of a dominant element; the first band is the newest
by position, which is the only claim a feed should make. It reads at
half size in every part: the sentence, the title, the time, the tile
letters, the rail's names and presence lines, the strip's posters at
72×108.

**The rail answers all four of the owner's notes.**

- *Friends withhold data.* Four sharing states, each drawn and each
  legible: the strip appears only when the person shares watches;
  reviews-only says "Doesn't share watching" in 18px at 66%, so the
  absence reads as their choice; listings-only reads the same way
  with a listing on the presence line; nothing shared says so. The
  You card mirrors your own state ("You don't share watching").
- *The strip is the point.* Three posters per watch-sharer, in the
  rail, at the card's foot — the few things they last watched, the
  fact the Feed excludes by rule.
- *Many friends.* You first, then seven by latest act, then "All 30
  friends"; the rail ends a window above the feed's foot and the
  column continues alone, one scroll region.
- *Paging.* Twenty bands, "Show older" appends twenty, the third ends
  the column at sixty with "That's the last sixty." — a count, which
  is true at any roster's pace. "3 new" queues arrivals at the head
  when the page is scrolled and prepends live at the top.

**Two things to fix in the spec, both small.**

1. **The strip needs its caption.** The designer's own doubt, and the
   render confirms it: Femi's three posters under "watched Big Buck
   Bunny" read as watched; the same three under "reviewed Charade"
   would read as reviewed. A *Recently watched* caption at 18px/66%
   above the strip, on both surfaces (the tab already has one), costs
   24px per card and makes the strip one fact regardless of the line.
2. **Card heights vary** (194 / 128 / 104 / 78) so the rail's rhythm
   is ragged. That is right — a card is as tall as what the person
   shares — but the You card's extra subtitle line and the note line
   should sit in the same slot so a reviews-only friend and You are
   the same height.

## The Friends page

A 700px left-aligned column of full cards at couch scale: You first,
then friends by latest act, each in its sharing state, the strip at
96×144 with the "all N" tile for watch-sharers, the Wants to watch and
Reviewed rows, the key and Remove friend in the footer, Add a friend
as a card at the foot. Readable at half size. The shared-values list in
its REASONING matches the rail's card line for line (head order, the
tile's three states, name 22/600, time 18/60%, presence 20/80%, note
18/60%, the strip's label and radius); the two are one component at
two widths, as intended.

**Its one problem is the empty right at 1920** — 1,100px of ground
beside a 700px column. The designer argues the column is the strip's
width and that two columns break linear order for a gamepad. The owner
raised wasted space once already; this page has more of it than any
band ever did. Two honest answers: accept it as Settings does (a
management page, visited to act, not to look), or take a two-column
card grid with a row-major nav graph (Left/Right within the row,
Up/Down across rows), which the input system already handles for the
Library grid. I recommend the grid at 1920, one column below 1500: a
page of thirty friends is a browse as much as a form, and the cards
have no order-dependence that a grid breaks (latest-act order is
readable row-major).

## The Watchlist beside the rail

State 13 works as P's anatomy at couch scale: title first, the ladder
and acquisition words in the seat, the pennant mast at the band's
right edge. Nothing new to decide; the width and the rail are the
Feed's.

## Verdict

**`G-couch-feed` replaces F as the proposed page**, with the strip's
caption and the aligned note slot. **`G-friends-page` is the Friends
tab**, with the two-column grid at 1920 to render in the next pass.
Together with the settled table from round 5 (the tile, the crop rule,
the scrim, the toolbar contract, "You" neutral, no motion beyond a
possible cursor ease) this is the whole design.

## What changes in the spec and the plan

- The spec's "What the user sees" comes from `G-couch-feed`'s and
  `G-friends-page`'s size tables, not F's. The lead is gone; the band
  is 224px at couch scale; the page is two columns with a fold at
  1700; the person card is one component at two widths with four
  sharing states; paging is a window of twenty to a cap of sixty with
  a queued head.
- The plan's phases 3 and 4 change (the band without a `:lead` size,
  the rail and the fold, the "N new" queue and the cap); phase 1 gains
  the person card's refactor (rail width, sharing states, the caption)
  and the identity tile's 48px size; a new phase covers the Friends
  page's grid. The Watchlist in bands stays out of scope.
- Records: UIDR-046 (the cinematic feed: bands, the rail, paging, the
  couch floors) amending UIDR-045 rules 3 and 5, UIDR-038 rules 7–10
  (the card's rules become the person card's, at both widths) and its
  *social-network chrome*; a note in UIDR-033. The couch floors go into
  the `user-interface` skill as a house rule for every surface.
