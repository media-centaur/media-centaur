---
status: in-progress
started: 2026-08-07
last_updated: 2026-08-07
---
# Input system 1.0 pass

## Goal

Bring keyboard/gamepad navigation to shipping quality for 1.0, page by
page, by fixing the *model* rather than each page's symptoms. Two
responsibilities are currently conflated and neither has a single owner:
**adjacency** (given a focused item and a direction, which item takes
focus) and **reveal** (what the viewport does so the user can see it).
Every defect found so far falls cleanly into one bucket or the other.
The pass is owner-driven, one page at a time, starting with Home.

## Status

Phase 1 (Home) shipped in v0.116.0 — every clause of the owner's spec traces
correctly, `mc-nav-trace` reports zero clipped steps across all four shelves,
and cursor-following motion glides in both axes via `core/scroll_glide.js`.

Phase 3 (the detail modal) implemented 2026-08-07 and verified by driving real
keydown through the live input system in a browser. Unshipped as of writing.

Next: the remaining pages, one at a time, owner-directed.

## The model

The organizing idea: **given a focused tile and a direction, which tile
takes focus, and what must the viewport do so it is visible.**

Three rules follow, and they are what this campaign implements:

1. **Geometry is the adjacency model; index arithmetic is an
   optimization of it.** Ask "what is to the right", not "what is
   index+1". The DOM rects already encode the answer.
   `core/spatial.js` has exported and unit-tested `findNearest()` since
   before this campaign, called from **nowhere** — the engine was
   half-intended already.
2. **Reveal has exactly one owner, and it is not CSS.** Scroll-snap is
   a *pointer* affordance — flick, release, settle. With a focus cursor
   there is nothing to settle: the focused item *is* the resting
   position. Shipping both means CSS silently overrides the input
   system.
3. **Entering a zone lands on an item touching the edge you came
   through.** Memory is preserved when the remembered item is on that
   edge; otherwise the nearest item that is. A zone may instead declare
   a fixed **anchor** when landing somewhere predictable is a product
   rule rather than a nav accident (the hero: entering it always means
   "press play").

## Home page spec (owner-authored, 2026-08-07)

Verbatim intent, for regression tests:

* Load → hero **Play** focused; Right → More info.
* Down from either hero CTA → Continue Watching, at the most recently
  focused card (first by default).
* Continue Watching: Left/Right through entries. Up from anywhere →
  hero **Play** (always Play, not the last-focused CTA). Down → Recently
  Added, most recently focused (far-left first by default).
* Recently Added: same shape. Up → Continue Watching (memory). Down →
  Coming Up, memory-restored **but only ever tile 1 or 2, never tile 3**.
* Coming Up is a mosaic, not a row (tile 1 large at left; tiles 2 and 3
  stacked at right, 2 on top):
  * from 1: Right → 2 (the **top** secondary, also when 3 secondaries
    render); Up → Recently Added.
  * from 2: Left → 1; Right → 3; Down → 3; Up → Recently Added.
  * from 3: Left → 1; Up → 2.
* Everything reachable by keyboard must be reachable by gamepad.
* Rows must scroll **smoothly**, without making the interface feel
  delayed or chunky.

## Diagnosis (measured, not assumed)

Against the live dev service on `:2160` with `mc-nav-trace`:

* **Focus adjacency on the shelves already works** — Left/Right through
  Continue Watching and Recently Added, and up/down memory in both
  directions. The owner's "left/right is broken" report is a *reveal*
  defect, not a focus defect.
* **Every card past the fold is clipped ~100 visual px on the right**
  (≈⅓ of a 317px card, focus ring included), on both scrolling rows.
  Cause: `scroll-snap-type: x mandatory` (`assets/css/app.css`).
  `scrollIntoView` asks for enough scroll to reveal the card; the snap
  engine then re-snaps to the nearest card-start boundary and
  undershoots. **A/B confirmed**: injecting `scroll-snap-type: none`
  drops clipping to 0 at every step.
* `behavior: "instant"` on top of that makes the row teleport a full
  card with a third of the target still hidden — the "chunky" feel.
* Coming Up is typed `SHELF` (a flat ±1 list over DOM order), so
  `2→Down`, `3→Left`, and `3→Up` are all wrong per spec.
* The marquee builds **up to 3 secondaries** (`home_live/logic.ex`), so
  a hardcoded 3-tile adjacency table would be wrong the moment a 4th
  release lands. Geometry is required, not preferred.
* Pure geometry is *not* sufficient for the hero: from a right-ward
  Continue Watching card, "More info" is horizontally nearer than
  "Play", so nearest-neighbour would pick the wrong CTA. Hence the
  declared-anchor half of rule 3.

## Decisions made

* `2026-08-07` — **Coherent path over cheap path**, owner call: fix the
  shared model (geometric adjacency, single `revealItem` owner, declared
  entry rule per zone) rather than special-casing Coming Up and patching
  two `if`s. Accepted cost: the shared `dom_adapter` reveal path is
  touched, so every other page inherits the change and needs a
  regression pass. Owner: *"I will always pay the price for coherence."*
* `2026-08-07` — **Scroll-snap and focus-driven scrolling are mutually
  exclusive.** Remove `scroll-snap-type` from `.row-scroll` rather than
  trying to make `scrollIntoView` cooperate with it.
* `2026-08-07` — **SUPERSEDED the same day (see the next entry): the glide
  belongs to CSS `scroll-behavior`, not `scrollIntoView({behavior:
  "smooth"})`.** Measured, and
  it reversed the plan: `scrollIntoView` with smooth **stops retargeting under
  fast input** and strands the row mid-glide — stalled dead at scrollLeft 1103
  with the cursor 300–950px outside the scrollport at a 220ms step rate, while
  the identical walk at 900ms was flawless. The container's own
  `scroll-behavior: smooth` retargets correctly and settles on the *identical*
  offset as an instant scroll (2462, zero clip). This also sharpens the
  ownership rule: **the input system owns WHERE the scroll lands; CSS owns HOW
  it gets there** — snap violated the first, `scroll-behavior` only touches the
  second. No rAF glide or damped spring was needed; that idea is dropped, not
  deferred.
* `2026-08-07` — **Neither browser smooth-scroll route works; the glide is
  ours (`core/scroll_glide.js`).** The CSS decision above was measured only at
  a 220ms step rate. At real key-repeat (~33ms) `scroll-behavior: smooth`
  fails just as badly as the `scrollIntoView` variant, for a different reason:
  it *does* retarget, but restarts its ease-in curve from rest every time, so
  the row never escapes the slow opening — the cursor ran **3015px off-screen
  while `scrollLeft` sat at 3**, then lurched the whole distance on key-up.
  Owner had independently proposed the right model: cursor moves instantly,
  the row chases, and **a further target scrolls faster**. That is an
  exponential approach — each frame closes a fixed fraction of the remaining
  gap — so speed depends only on distance and retargeting is just a new number
  with no easing to restart. Measured steady-state lag: **~70px at the
  gamepad's 180ms repeat**, ~200px at 100ms. `scroll-behavior` is now banned
  from every nav-driven container *including `html`*, because it also
  intercepts direct `scrollLeft`/`scrollTop` assignment and would fight the
  glide's per-frame writes.
* `2026-08-07` — **`data-nav-reveal` replaces the home page behavior.** Owner
  reported the page "JERKS suddenly" entering the hero from below. Cause: the
  home behavior scrolled the window to the top on `onZoneChanged` — a second
  scroll of the same box, racing the reveal, and necessarily instant because a
  smooth one would be rewound by the reveal's measure-and-restore. Fixed at
  the seam instead: an ancestor may carry `data-nav-reveal` to declare itself
  the thing worth showing, so the hero reveals its whole backdrop rather than
  just the CTA. `home_behavior.js` and `data-page-behavior="home"` are deleted
  — the page needs no behavior at all now.
* `2026-08-07` — **Time constant τ = 110ms, pending real hardware.** Tested
  70/110/150 at 33ms and 180ms repeat. The 180ms column is clean and monotonic
  (23 / 73 / 132px lag); the 33ms column is not trustworthy headless, because
  under SwiftShader the input rate approaches the rAF cadence and the
  comparison measures frame starvation rather than the algorithm. τ is a
  one-line constant — retune on the media-center display if the feel is off.
* `2026-08-07` — **Shelves are spatial everywhere, not just the mosaic.** Hero,
  Continue Watching, Recently Added and Coming Up stay one context type with
  one navigation path (`_shelfNavigate`): geometry → nav graph → sequence. A
  separate MOSAIC type for Coming Up would have been the bolt-on. For a single
  row geometry and index arithmetic agree, so the rows behave exactly as before.
* `2026-08-07` — **The `focus_first` directive is now `enter_context`,
  carrying the direction travelled.** The old name lied — it restored memory,
  not the first item — and entry needs the direction to honour the edge rule.
* `2026-08-07` — **The entry-edge rule is scoped to SHELF contexts for now.**
  The mechanism is uniform and every `enter_context` directive already carries
  its direction; only the SHELF gate in `_enterContext` limits it. A vertical
  MENU entered from above should land on its first item by the same logic —
  that lands as each page is reviewed, so the rollout is staged rather than a
  silent behaviour change on pages nobody has looked at yet. **Convergence
  point: the gate is removed when the last page in "Next steps" is done.**
* `2026-08-07` — **Mouse wheel over a scrolling row: deferred.** It
  conflicts with page scroll and has no obvious right answer. Owner
  explicitly parked it.
* `2026-08-07` — **"Never tile 3" is not a special case.** It is the
  entry-edge rule: tile 3 does not touch Coming Up's top edge, so it is
  not a candidate when entering from above.

* `2026-08-07` — **The shelf-framing rule is "descending fully reveals the
  shelf below", and the reserve is sized from that shelf — not a round
  number.** `--shelf-reserve-below` is `calc(var(--marquee-h) + 5rem)`: one
  whole marquee (the tallest shelf) plus its heading and the inter-section
  gap. `--marquee-h` moved out of the component into `:root` so the height and
  the reserve sized to reveal it are one number with two consumers. Owner's
  framing — "we can just move far enough down that coming up is fully
  visible" — is what settled this; a consistent per-row anchor was the
  alternative and would have needed ~310px of reserved trailing space, which
  is now NOT wanted.
* `2026-08-07` — **UI-scale compatibility: express the reserve in `rem`/`px`,
  never `vh`.** The shell scales with `zoom`, which multiplies every rendered
  length, so the reserve and the shelf it is sized to reveal grow together and
  the rule survives untouched. A bare `Nvh` renders at `N × scale` under zoom
  (the trap `--pvh` exists for) and would make the reserve balloon relative to
  its shelf as the user scales up. Verified at four scales (effective 0.49 /
  0.70 / 1.05 / 1.40): the next shelf is 100% visible at every one, and at the
  smallest the page does not scroll at all because nothing needs to.
* `2026-08-07` — **Shelf framing is `scroll-margin`, not a per-step scroll
  distance.** Owner asked that moving down a shelf lift the focused row and
  drag the next one into view, rather than the row merely being on screen.
  Implemented by giving each shelf's cards a reserve below them
  (`--shelf-reserve-below`), so "bring this card into view" can no longer be
  satisfied without the row rising far enough to expose that reserve — which
  the next shelf occupies. A per-step pixel amount was rejected: it drifts the
  moment a card size or row header changes, and it has no relationship to what
  is actually below. Measured result: Play → Continue scrolls 119px with the
  hero still 83% visible and Recently going 77% → 100%; Continue → Recently
  scrolls to 354 and brings Coming Up 18% → 100%.
* `2026-08-07` — **The home page has only ~365px of scroll range at 1080p**
  (document 1445, viewport 1080), so shelf framing is necessarily subtle and
  the last shelf cannot rise — nothing is below it to reveal. Raising the
  reserve past the page's scroll range buys nothing. Making the travel more
  cinematic is a *content-height* conversation (taller cards, taller hero, or
  reserved trailing space), not a navigation one.

* `2026-08-07` — **The input method starts as KEYBOARD, not MOUSE.** Focus was
  always parked on the hero's Play button at load, but the ring is gated on
  `data-input`, which started at `mouse` — so a fresh load (or a hard reload)
  looked like nothing was selected. Changed in both places that decide it:
  `InputMethodDetector`'s default and the static `data-input` on
  `root.html.heex`, so the very first paint agrees before JS runs. This is a
  ten-foot appliance; a genuine mouse user is switched back by their first
  pointer movement. The gamepad hint bar is gated on `gamepad` specifically,
  so nothing else surfaces.
* `2026-08-07` — **The shelf reserve includes `--nav-ring-reserve`.** Owner
  reported that descending onto the last shelf still nudged the page. Cause was
  not the shelf framing but the pre-existing 1rem ring reserve every nav item
  carries (so a focused ring is not eaten by TV overscan at the scrollport
  edge): arriving at a shelf revealed it flush to the edge, and focusing it
  then scrolled again by that 1rem. Fixed by composing the two — descending now
  reveals the next shelf *including the room its ring will need*, so arriving
  costs no further movement. `1rem` became `--nav-ring-reserve` so the global
  rule and the shelf reserve share one number.
* `2026-08-07` — **Only a shelf with a shelf beneath it reserves room**
  (`.home-shelf:has(~ .home-shelf)`). The reserve is room for the *next* shelf;
  the last one has none, and giving it one made it saturate against the page
  bottom and drag the page down for no gain.

* `2026-08-07` — **A shelf has ONE resting position, whichever direction you
  arrive from** (`data-nav-reveal-block="end"`). Owner's rule: going up from
  Recently to Continue should land where you would be if you had come *down*
  to Continue from the hero. `scrollIntoView`'s "nearest" cannot do that — it
  aligns to whichever edge you approached from, which is why ascending
  previously moved nothing. The surface now declares its alignment and the
  reveal honours it. Verified identical in both directions at three scales:
  Continue 125/377/628, Recently 359/729/1097.
  The declared alignment is a *preference*: at large UI scales a shelf's
  reserve can outgrow the viewport, and honouring "end" would then push the
  focused card off the top. `revealItem` checks and falls back to a minimal
  reveal, because keeping the card on screen beats framing it.

## Next steps

1. ~~**Phase 1 — Home.**~~ Done: entry rules (edge-constrained memory + hero
   anchor), Coming Up as a geometric mosaic, single `revealItem` owner,
   scroll-snap removed, and the glide moved into `core/scroll_glide.js`
   (`scroll-behavior` was an intermediate step that did not survive
   measurement — see Decisions).
2. ~~**Confirm on real hardware**~~ — owner: "it feels fine". τ stays at 110ms.
3. ~~**Should ascending re-frame too?**~~ Owner: yes, and gave the rule — a
   shelf lands where it would have landed coming down. Done via
   `data-nav-reveal-block="end"`.
4. ~~**Should vertical scrolling glide too?**~~ Owner: yes, "so the eye can
   follow it". Done — the glide animates whichever containers a reveal moves,
   so the page glides on the same mechanism as the rows, on every page.
5. **Phase 2 — the cursor itself animates.** Owner-proposed, designed and
   agreed 2026-08-07. Layer 1 shipped; layer 2 built and then reverted.

   * ~~**Layer 1 — the cursor stops short of the edge.**~~ Done.
     `scroll-padding-inline` grew from the ring's 4px to a whole card, so the
     cursor parks one card in and the row scrolls beneath it. Measured before:
     pinned 1px from the edge on card 6 of 16 and stayed there. After: a
     settled `R1.02` cards of peek from card 4 onward, symmetric on the way
     back, and the card still reaches the edge at the true ends of the list.
     Non-degenerate at every UI scale (1.0 → 3.0 measured, table in UIDR-018).
   * **Layer 2 — the ring travels between items. BUILT, TRIED, REVERTED
     2026-08-07 on owner call.** Not a defect — it worked, and measured within
     2px of its element on every axis at four UI scales. The owner did not like
     how it felt: *"this whole moving cursor effort is falling flat for me... I
     liked everything we had before this."* The per-element ring is back and the
     scroll glide (which the owner does like, both axes) is untouched.

     Do not rebuild it without a fresh owner decision. If it is ever revisited,
     these are the findings, all measured, so the work does not start from zero:

     - **Chase the SETTLED rect, never the live one.** The obvious design —
       cursor chases the focused element's current rect each frame — wobbles at
       exactly the wrong moment. While a row scrolls, the focused card is itself
       in motion; with both easing on the same time constant the ring swings out
       to A/e ≈ **37% of a card width** at t = TAU before returning. Handing it
       the post-scroll rect makes the target stationary from the first frame, so
       "the row slides underneath a parked ring" needs no code at all.
       `revealItem` can supply that rect for free — it has already measured
       every pending scroll offset.
     - **UNITS, twice, and both invisible at scale 1.0** — i.e. invisible on the
       machine they were written on. (a) Adding a `scrollLeft` delta (layout px)
       to a `getBoundingClientRect` (visual px) put the ring a **constant 56px**
       off once a row scrolled. (b) Then converting the ROOT scroller's delta
       the same way put it a **fraction** of the travel behind —
       `(1 - scale) / scale`, measured at 43% of every move between shelves —
       because `document.scrollingElement` sits OUTSIDE the zoom it applies and
       reports visual px already, while every nested scroller reports layout px.
       This distinction is worth knowing for anything mixing the two families;
       `hooks/sidebar_tooltip.js` documents the related rect-vs-transform half.
     - **`scrollIntoView` is not idempotent** under `block: "nearest"`. Called
       again from the position it just produced it moves further —
       measured 207.62 → 210.48 → stable. So `revealItem`'s recorded destination
       is ~3 layout px short of satisfying its own `scroll-padding`. Left as-is:
       2 visual px, below anything worth a per-keypress extra layout. Under
       `block: "end"` (the home shelves) it is already at its fixed point.
     - Design constraints that all held in the build, if it matters later: adopt
       shape and colour from the target rather than knowing about variants; cut
       rather than fly when crossing an overlay layer; one rAF loop; no
       per-frame DOM reads.

     **Kept from the effort:** `mc-nav-trace` gained a `peek` column (room
     beyond the focused card, in card widths — the "does the cursor stop before
     the edge" number) and learned to separate *clipped at rest* (a finding)
     from *still moving* (what held input looks like), so it no longer cries
     wolf. Both are useful for every remaining page.

6. ~~**Phase 3 — the detail modal.**~~ Done 2026-08-07, owner-specified,
   verified in a real browser (`chromium-probe`, driving real keydown through
   the live input system on the dev server, not `render_click`). Recorded as
   [UIDR-019](../decisions/user-interface/2026-08-07-019-detail-modal-two-regions.md).

   The modal was one flat list of every focusable element in DOM order: getting
   from Play to an episode meant walking past the buttons, and BACK closed the
   whole modal from anywhere inside it. It is now two zones — `detail_actions`
   (TOOLBAR) over `detail_list` (a new TREE context) — and applies to every
   detail type, not just TV: a movie simply has no second region, so DOWN is
   inert and BACK closes, with no conditional model.

   What generalized rather than being special-cased:

   * **BACK moved out of the type dispatch.** It was a `case Action.BACK` in
     eight transition functions with the ordering between them implicit.
     `_backTransition()` now answers it once by walking containment. "BACK
     anywhere in the episode list goes to Play, BACK from Play closes the
     modal" is one rule, not two cases.
   * **Overlays can declare regions** (`data-nav-overlay` → `config.overlays`),
     with their topology merged over the page graph while open. Anything
     without the attribute stays flat MODAL.
   * **`entryDefaults`** lets a context name where it opens when it has no
     remembered position — `detail_list` uses `[data-resume-target]`, so the
     body opens on the episode Play would play. Position memory then takes over
     and is scoped to one opening of the overlay.

   Two things found while verifying, both fixed rather than reported:

   * **The watched toggle was unreachable by keyboard** and had been all along.
     Sub-focus entered only the *first* `[data-nav-sub-item]`, and every episode
     row with a synopsis carries the disclosure chevron first. RIGHT now walks
     along an item's controls.
   * **A deferred origin-focus restore could fire into a reopened overlay.**
     `_restoreOriginFocus` queues a rAF; closing one detail modal and opening
     another lands both transitions before that frame runs, and the restore
     would then yank the cursor out onto the page grid. Guarded on `inOverlay`.
     Surfaced by a unit test, not by use.

   Deliberately dropped: the list-wide "Show details" toggle is no longer a nav
   item. It sat between the action row and the first season, interrupting the
   one path users walk; owner's call is that it belongs in Manage. Mouse-only
   until it moves there.

   Open question left in the record: UP at the top of the body does not climb
   to the action row. BACK is the documented way out; revisit if it reads as a
   dead end in use.

7. **Remaining pages**, owner-directed, one at a time — same two
   questions each (does adjacency match intent; is the focused item
   fully revealed). Library, Incoming, Settings, Status, Review /
   Reconcile, Watch History, Guide.

   Regression smoke after Phase 1 (`mc-nav-trace`, 2026-08-07): every page
   still navigates, no clipping anywhere — the shared reveal/glide change
   broke nothing. Leads it turned up, for those pages' own turns:

   * **Incoming** — on load `data-nav-context` reads `coming_up_list` while
     focus is actually in `omnibox`. Cursor start and the projected context
     disagree; suspect `cursorStartPriority` vs. where focus really lands.
   * **History** — RIGHT is inert in a 51-item grid. Single-column list
     rendered as a GRID? Check the column count the reader derives.
   * **Status** — DOWN is inert from index 4 of 8 while items remain below.
     Likely the same column-count question.
8. **Remove the SHELF gate on the entry-edge rule** once the pages above are
   done — the named convergence point from the Decisions entry. The mechanism
   is already uniform; only `_enterContext`'s type check limits it.
9. **Resolve the deferred mouse-wheel question** once the keyboard and
   gamepad models are settled.

## Completion criteria

* Every page's adjacency matches an owner-stated spec, verified with
  `mc-nav-trace` (not just green unit tests).
* `mc-nav-trace` reports **zero clipped steps** on every page that has a
  scrolling row.
* Keyboard and gamepad reach the same items everywhere — no
  keyboard-only affordances.
* Scrolling is smooth under held input on the real media-center
  hardware, with no perceived interface delay.
* `bun test assets/js/input/` and `mix precommit` green.

## Pointers

* Model + DOM contract: [`docs/input-system.md`](../docs/input-system.md),
  the `input-system` skill.
* Framework: `assets/js/input/core/` — `focus_context.js` (state
  machine), `nav_graph.js` (cross-zone edges), `spatial.js`
  (`findNearest`, currently unused), `dom_adapter.js` (the only module
  touching the DOM), `orchestrator.js`.
* App config: `assets/js/input/config.js` — zone layouts, instance
  types, cursor-start priority.
* Home surfaces: `lib/media_centaur_web/live/home_live.ex`,
  `components/{hero_card,continue_watching_row,poster_row,coming_up_marquee}.ex`.
* Row CSS: `.row-scroll` and variants in `assets/css/app.css`.
* Verification tool: `~/scripts/agents/mc-nav-trace` — key sequence →
  per-step focus context, zone, index, scroll offset, and clipped px.
  Beware the units trap it documents: the app's UI-scale transform means
  `getBoundingClientRect()` and `scrollLeft` are different coordinate
  spaces.
