---
status: accepted
date: 2026-08-07
---
# Focus cursor and scroll behaviour

## Context and Problem Statement

Media Centaur is driven from a couch by keyboard and gamepad, so the focus cursor is the only cursor and how the page moves under it is the interface. The behaviour had accumulated rather than been designed: which item takes focus and what the viewport does about it had no owner, and every defect fell into one of them. This record is the contract a new page is checked against.

## Decision Outcome

1. **The input system owns the scroll, destination and motion; CSS owns none of it.** No `scroll-snap-type` and no `scroll-behavior: smooth` anywhere a nav cursor goes: snap re-snaps after every reveal, and smooth restarts its ease on every retarget under held input. The glide lives in `assets/js/input/core/scroll_glide.js`.
2. **Where to scroll is asked, not computed.** `revealItem` scrolls instantly, reads where the browser landed, restores the offsets, and glides to the recorded destination. Destinations are therefore declared as scroll margins and padding on the elements: CSS states the geometry, the input system decides when to consult it.
3. **Motion is exponential approach**: a fixed fraction of the remaining gap per frame, frame-rate independent and safe to retarget mid-flight.
4. **Focus is instantaneous; the scroll animates behind it.** SELECT mid-glide activates the card the user is on.
5. **Vertically, a shelf has one resting position whichever way you arrive.** A surface that wants it declares `data-nav-reveal-block` instead of accepting `scrollIntoView`'s "nearest"; if honouring it would push the item off the opposite edge, the reveal falls back to minimal. A surface whose items differ in height declares `data-nav-reveal` on the composition so every item shares one resting position; the reveal subject carries the same ring reserve as an item.
6. **Descending reveals what is below.** Each shelf reserves one whole shelf beneath itself (`scroll-margin-bottom`), so revealing a card lifts the row far enough to expose the next shelf. A shelf with nothing below reserves nothing (`:has(~ .home-shelf)`).
7. **Horizontally, the cursor stops one card short of each end**, then the row scrolls under a stationary cursor: a card's width is reserved at both ends (`scroll-padding-inline`). A whole card, never a sliver.
8. **At the true ends of a list the card reaches the edge.** That is how "nothing more this way" is said, and it falls out of the scroll saturating.
9. **The focus ring is never clipped.** The ring sits outside the border box, so reserves exceed it generously: `--nav-ring-reserve: 1rem` on the block axis (TV overscan eats the edge) and `--row-end-reserve: 0.5rem` at row ends.
10. **Every reserve degrades gracefully.** UI scale is a root `zoom`, so `rem`/`px` reserves scale with content while the viewport does not; a reserve also yields to at most a third of the space left after the focused card, keeping card plus reserves inside the scrollport at any scale (measured at four scales: no clipping). Never express a reserve in `vh`; under `zoom` it balloons.
11. **Entering a zone lands on the item touching the edge you crossed.** Adjacency is geometry, not list order; within that band remembered position wins.

### Considered and rejected

A single focus ring travelling between items instead of one appearing on each. It was built, worked within 2 px at four scales, and was reverted on the owner's call: the motion did not feel better than the cut, and it cost an overlay, a second animator and a transparent-ring override on every focus rule. Recorded so the idea is not retried from scratch.

### Consequences

* Rules 7 and 10 spend horizontal room; at high UI scale a reserved card width is a visible fraction of a small row.
* CSS scroll features are off the table repository-wide, including where they would be harmless.
* `mc-nav-trace` reports `clip` (rule 9) and `peek` (rules 7, 8, 10) per step.
