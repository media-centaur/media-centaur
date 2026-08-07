---
status: accepted
date: 2026-08-07
---
# Focus cursor and scroll behaviour

## Context and Problem Statement

Media Centaur is driven from a couch, by keyboard and gamepad, with no pointer.
The focus cursor is therefore not an accessibility affordance layered onto a
mouse-first design — it is the only cursor there is, and where it sits and how
the page moves under it *is* the interface.

The 1.0 review found the behaviour was not designed, it had accumulated. Two
separate questions — **which item takes focus** (adjacency) and **what the
viewport does about it** (reveal) — had no owner between them, and every defect
fell into one bucket or the other: rows that scrolled the focused card a third
of the way off screen, a cursor that pinned itself to the right edge and stayed
there for the rest of the list, a page that jerked when returning to the hero, a
shelf that came to rest in a different place depending on whether you arrived
going up or going down.

Fixing those one at a time would have produced a pile of special cases. What was
missing was a stated contract: a small number of rules from which the correct
behaviour follows, that a contributor can check a new page against.

This record is that contract. It is deliberately written as felt behaviour
first — what the person on the couch should experience — with the mechanism
named second, because the mechanism is replaceable and the experience is not.

## Decision Outcome

### 1. The input system owns the scroll. CSS owns none of it.

Both the destination *and* the motion. This is the rule the others depend on,
and it is not the obvious split — CSS offers `scroll-snap-type` and
`scroll-behavior: smooth`, and both look like they are helping.

* **Snap is a pointer affordance.** Flick, release, settle somewhere sensible.
  With a focus cursor there is nothing to settle, because the focused element
  already *is* the resting position. Ship both and snap wins: `scroll-snap-type:
  x mandatory` re-snapped after every `scrollIntoView` and parked the focused
  card ~100px — a third of a card — outside the scrollport, on every card past
  the fold.
* **`scroll-behavior: smooth` does not survive held input.** It restarts its
  ease-in on every retarget, so at a 33ms key repeat the cursor ran 3015px off
  screen while `scrollLeft` sat at 3.

So: no snap, no `scroll-behavior`, anywhere a nav cursor goes. The glide lives
in `assets/js/input/core/scroll_glide.js`.

### 2. Where to scroll is asked, not computed.

`revealItem` scrolls instantly, reads where the browser landed, puts the offsets
back, and glides to the recorded destination. This looks roundabout and the
alternative is worse: computing the destination ourselves means reimplementing
`scrollIntoView`'s "nearest" algorithm including `scroll-padding`, borders, and
writing modes. Nothing paints between the jump and the restore, so there is no
flicker.

The consequence worth knowing: **destinations are expressed declaratively, as
scroll margins and padding on the elements themselves.** That is why the rules
below are CSS lengths rather than JavaScript constants — see rule 1, which this
does not contradict: CSS states the geometry, the input system decides when to
consult it and animates the result.

### 3. Motion is exponential approach.

A fixed fraction of the remaining gap per frame. Speed is therefore proportional
to distance remaining — a long jump starts fast and eases in, a short one is
almost immediate — and the same code is frame-rate independent and safe to
retarget mid-flight. Held input just keeps moving the target; nothing restarts.

### 4. Focus is instantaneous; the scroll animates behind it.

`focus()` is synchronous and the glide catches up. The cursor is never where the
animation is, so SELECT mid-glide activates the card the user is actually on,
not the one still sliding into place. Input never waits for animation.

### 5. Vertically, a shelf has one resting position, whichever way you arrive.

`scrollIntoView`'s `"nearest"` scrolls as little as possible, which means it
aligns to whichever edge you approached from — so descending to a row and
ascending to it leave the page in two different places, and the same row looks
like two different rows. A surface that wants one resting position declares its
alignment (`data-nav-reveal-block`) instead of accepting the minimum.

The declared alignment is a *preference, not a promise*: if honouring it would
push the focused item off the opposite edge (possible at large UI scales, where
a reserve can outgrow the viewport), the reveal falls back to a minimal one.
Keeping the item on screen beats framing it.

**A surface whose items differ in height must say what to frame.** A reveal
frames whatever it is handed, and by default that is the focused item — which is
correct only while every item in the surface shares a bottom edge. Rows satisfy
that by construction and need no declaration. The Coming Up mosaic does not: one
tall primary tile beside two half-height secondaries, where moving to a secondary
scrolled the page up 129px, because a shorter tile's bottom aligned to the
viewport bottom sits higher. Such a surface declares `data-nav-reveal` on the
composition, and every item in it then shares one resting position.

The reveal subject must carry the same ring reserve as an item (rule 9). It is
what actually gets scrolled, so reserving on the item alone lets a surface that
declares a subject quietly park its content flush against the screen edge.

### 6. Descending reveals what is below.

Moving down to a shelf lifts it and brings the *next* shelf fully into view. Not
a per-step pixel amount — that drifts out of alignment the moment a card size or
heading changes, and it has no relationship to what is actually down there.
Instead each shelf reserves space beneath itself (`scroll-margin-bottom`) sized
as one whole shelf, so "bring this card into view" can no longer be satisfied by
the card merely being on screen: the row must lift far enough to expose the
reserve, and the next shelf is what occupies it. Nobody computes a distance.

A shelf with nothing below it reserves nothing (`:has(~ .home-shelf)`) — the
reserve is room for the next shelf, and given one anyway it saturates against the
page bottom and drags the page down for no gain.

### 7. Horizontally, the cursor stops one card short of each end.

Then the row scrolls underneath a stationary cursor. Same mechanism, inline
axis: reserve a card's width at both ends (`scroll-padding-inline`) and "bring
this card into view" keeps moving the row until a whole neighbour fits beyond
the focused one. The hand-off from *cursor moves* to *row moves* is not coded;
it is what the reserve makes true.

Before this rule the cursor advanced to 1px from the right edge on the 6th card
and stayed pinned there for the remaining ten — the eye had no signal that more
content existed until it arrived.

**A whole card, never a sliver.** These rows are a clean card grid, and a
permanently half-sliced poster reads as a rendering fault from ten feet, not as
an invitation to keep going.

### 8. At the true ends of a list, the card does reach the edge.

That is how "there is nothing more this way" is communicated, and it falls out
of the scroll saturating rather than being special-cased.

### 9. The focus ring is never clipped. Not at any scale, not at any position.

The ring is drawn *outside* the border box (2px outline + 2px offset) while
`scrollIntoView` aligns the *border box* to the edge, so every reveal wants to
clip it by exactly the 4px it sticks out. Reserves must therefore exceed the
ring, and they are generous rather than exact:

* `--nav-ring-reserve: 1rem` on the block axis — this is a ten-foot interface,
  where TV overscan eats the outer edge of the picture and a ring a few pixels
  from the boundary is simply gone.
* `--row-end-reserve: 0.5rem` at the inline ends of a card row. An exact-fit
  reserve puts the ring's outermost pixel row on the clip boundary, where it
  survives only as long as nothing rounds against it.

A ring pressed against an edge reads as a cropped card, not as a cursor.

### 10. Every reserve degrades gracefully, and none of them degenerate.

UI scale is a root `zoom`, which multiplies every rendered length. Lengths in
`rem`/`px` therefore scale in lockstep with the content they are sized against
and the rules keep holding — but the *viewport* does not grow, so in layout
pixels it shrinks as the user scales up. A row showing 4 backdrop cards at scale
1.0 shows fewer than 2 at scale 2.0, and a flat one-card reserve at both ends
would there exceed the row and leave the focused card nowhere to sit.

So a reserve also yields to what is actually available — at most a third of the
space left over once the focused card has taken its share, which keeps card plus
both reserves strictly inside the scrollport for any card narrower than its row.
Measured, walking a backdrop row at four scales:

| UI scale | cards visible | peek achieved | clipped |
|---|---|---|---|
| 1.0 | 4.02 | 1.00 card | no |
| 1.5 | 2.62 | 0.54 card | no |
| 2.0 | 1.92 | 0.31 card | no |
| 3.0 | 1.22 | 0.07 card | no |

Full peek where there is room, a graceful sliver where there is not, and no
scale at which the geometry breaks.

**Never express a reserve in `vh`.** Under `zoom` a bare `Nvh` renders at
N × scale — the trap `--pvh` exists for — so a `vh` reserve balloons relative to
the thing it was sized to reveal as the user scales up.

### 11. Entering a zone lands on the item touching the edge you crossed.

Adjacency is geometry, not list order. Coming down into a row lands on an item
along its top edge; coming in from the left lands on one at its left edge; within
that band, remembered position wins. Rules that would otherwise need stating
separately — "never land on the bottom-right tile of the mosaic when arriving
from above" — stop needing to be stated.

## Consequences

* Good, because each rule is checkable against a running page rather than being
  a matter of taste. `mc-nav-trace` reports `clip` (rule 9) and `peek` (rules
  7–8, 10) per step, so a new page's compliance is one invocation.
* Good, because the rules compose. Rules 5–8 are the same reserve mechanism on
  two axes, and rule 11 makes several would-be special cases disappear.
* Good, because the reserves are declarative and local. A component that changes
  its card size does not have to find and update a scroll constant somewhere
  else.
* Bad, because rules 7 and 10 spend horizontal room: a card's width at each end
  is reserved rather than filled, which at high UI scale is a visible fraction
  of a small row. Judged worth it — a row where the cursor pins to the edge
  hides the fact that the list continues, which is worse than showing one fewer
  card.
* Bad, because "the input system owns the scroll" means CSS scroll features are
  off the table repository-wide, including where they would have been harmless.
  The alternative is a rule with exceptions, and the two measured failures above
  were both cases where the feature looked harmless.
* Neutral, because the mouse is not covered. The wheel already scrolls the page,
  so what it should do inside a horizontally scrolling row is an open question,
  deliberately deferred until the keyboard and gamepad models had settled — which
  is what this record does. Revisit with a pointer in hand.

## Considered and rejected

**A single focus ring that travels between items**, rather than one appearing on
each element in turn. Rules 3 and 4 govern the *row's* motion; this would have
extended the same treatment to the ring itself, on the theory that a ring which
moves is easier for the eye to follow across a room than one that blinks.

It was built and it worked — within 2px of its element on every axis at four UI
scales — and it was **reverted on the owner's call** after use: the motion did
not feel better than the cut, and it changed a ring that everyone already reads
correctly. Ships nothing; costs an overlay, a second animator, and a
transparent-ring override on every focus rule in the stylesheet. The scroll
glide, which is the motion people do want, is unaffected.

Recorded because the idea is an appealing one that will occur to someone again.
The measurements — including why chasing the element's *live* rect wobbles by
37% of a card width at exactly the wrong moment, and two unit bugs that are
invisible at scale 1.0 — are in `campaigns/input-system-1.0-pass.md` so a future
attempt starts from what was learned rather than from scratch.
