# TV Modal Auto-Orient — Design

*2026-08-05 · status: implemented · revises
[2026-08-04 TV detail orientation](2026-08-04-tv-detail-orientation-design.md)*

## Problem

The 2026-08-04 design killed the TV auto-scroll and collapsed every season,
because auto-scrolling landed the user mid-list with no hero, no orientation,
and none of the page's design investment on screen. That diagnosis was correct
*for the page as it existed*.

Two things have since changed the constraint:

- The **orientation block is sticky** (2026-08-05 sticky-orientation design) —
  identity lockup, season hairline, metadata, play controls and synopsis pin to
  the top of the scrollport instead of scrolling away.
- The **scroll gutter is always reserved**, so arriving mid-document no longer
  re-flows the content.

Opening mid-list therefore no longer costs the orientation — the block that
answers "where am I" is on screen either way. What the collapse costs instead
is the common action: resuming a series means opening the modal, finding the
current season among up to 30 rows, expanding it, and hunting for the next
episode.

## Design

**Core idea:** `ViewModel.Orientation` is the detail page's single answer to
"where am I in this series." Which season is open and where the scrollport sits
are the *same question* the hairline and the Play label already answer — they
just weren't asking.

| Series state | Seasons | Scroll on open |
|---|---|---|
| In progress | season holding the next episode expanded | next episode centered in the visible region |
| Unstarted | season holding the first episode expanded | none — opens on the hero |
| Complete | all collapsed | none |
| Movie / movie-series | unchanged | unchanged |

An unstarted series has a *first* episode, not a next one: there is no position
to return to, and a first look should get the full cinematic reveal. A completed
series expands nothing, so its rows stay a compact rewatch index.

### Landing position

The orientation block pins over the top of the scrollport, covering **54%** of it
on a 1920×1080 display. Centering the target against the raw scrollport therefore
lands it *behind* the block — verified in the browser before the fix: target top
404, block bottom 520 (visual px).

Centering happens in the region **below** the pinned block, expressed as
`scroll-padding-top` on the scrollport — the platform's own name for "optimal
viewing region", which `scrollIntoView({block: "center"})` centers within. The
hook measures the block and sets it; it is left set so later programmatic
scrolls (keyboard/gamepad stepping through episode rows) also land clear.

> **Unit hazard.** The media-center UI runs under a `--ui-scale` transform, so
> `getBoundingClientRect()` returns *visual* pixels while `offsetHeight`,
> `clientHeight` and computed `top` return *layout* pixels. Mixing them silently
> doubles one side of the arithmetic. The hook uses layout pixels throughout.

### Scroll gating

`data-scroll-to-resume` on `#detail-content` is the **sole** signal the
`ScrollToResume` hook reads. Previously the hook scrolled whenever it found a
`[data-resume-target]` row, which worked only by accident of what got rendered;
making the signal explicit removes that implicit rule.

The flag is needed because the two concepts genuinely diverge in one state: an
unstarted series highlights its first episode (so the row carries
`data-resume-target`) but must not scroll. The highlight attribute cannot double
as the scroll signal.

## Components

- `ViewModel.Orientation` — two pure projections beside `season_fraction/1`:
  `initial_expanded_seasons/1` and `autoscroll?/1`.
- `Live.EntityModal.apply_modal_params/2` — seeds `expanded_seasons` from the
  orientation on selection change; `toggle_season` owns it thereafter.
- `Components.DetailPanel` — renders `data-scroll-to-resume` from
  `autoscroll_resume?/1`.
- `assets/js/app.js` — `ScrollToResume` gates on the flag and reserves the
  pinned block before centering.

## Rejected alternatives

- **Land the episode directly under the pinned block.** Wastes no space, but
  shows zero watched context; the centered variant reads as "here's where you
  are" rather than "here's the top of the rest".
- **Expand the current season without scrolling.** Preserves the hero reveal for
  every state, but leaves the next episode far down a 24-episode season — it
  solves the finding problem only for short seasons.
- **Move `orientation` onto `SeriesDetail` as a field.** Considered to satisfy
  the module's "computed once" docstring, since `EntityModal` and `DetailPanel`
  now each call `Orientation.build/2`. Rejected: `DetailPanel` is polymorphic and
  builds orientation from the `seasons_view` + `resume` attrs it already
  receives, so an added attr would give it *two* ways to obtain the value and a
  caller passing one but not the other would silently lose the hairline. Two
  invocations of one pure builder from the same inputs is not two
  representations; a dual-source attr would be.

## Surfaced defect — pinned backing registration

Opening pinned by default exposed a pre-existing misregistration from the
sticky-orientation change: `.detail-orientation::before` repaints the backdrop as
the block's opaque backing, and it drifted from the panel backdrop underneath it —
visible as a second image over the first.

Both layers are width-dominated `cover` fits anchored top-left, so their scale is
set entirely by their box width, and the widths differed by the reserved scrollbar
gutter: the panel backdrop spans the full panel (deliberately extending under the
rail so it sits over the picture), while the block lives inside the scroller and is
narrower by exactly that gutter. Measured 1905 vs 1895 visual px — coincident at the
left edge, ~10px apart by the right.

CSS cannot read its own scrollbar width, so the `ScrollRailWidth` hook publishes it
as `--modal-rail-w` on the scrollport and the backing extends right by it. Verified:
both boxes now compute to `952.333px`.

Not caused by the auto-orient change — nothing in it touches CSS or layout — but it
became the first thing on screen for every in-progress series, so it is fixed here.

## Known incoherence — scheduled

`DetailPanel.autoscroll_resume?/1` returns a bare `true` for every non-TV type
rather than deriving it, because movie-series has no view model to derive it
from (it loads as a plain map from `Library.load_modal_entry/1`). This preserves
the pre-existing behaviour exactly — a movie-series with nothing watched renders
no target row, so the hook finds nothing to scroll to.

**Convergence point:** when movie-series gains a `SeriesDetail` equivalent
(playable-item-versions campaign), the derivation moves there alongside
`Orientation.autoscroll?/1`. Recorded at the call site.

## Verification

Unit tests cover both projections across all three states. LiveView tests cover
expanded-season rendering and the presence/absence of `data-scroll-to-resume`
per state.

Measured in a real browser at 1920×1080 against the live library — 30 Rock
(S4E10, seasons 1–3 collapsed above), Scrubs (S1E15 of 24), The Wire (S1E2, too
near the top to fully center), Babylon 5 (S1E7, partial resume), Baskets
(unstarted), Mr Inbetween (complete), and The Conjuring Collection
(movie-series). Every in-progress case lands the next episode visible and clear
of the pinned block; unstarted and complete open on the hero; the movie-series
path is unchanged.

The lockup logo sits above the episode list and has no reserved height, so a
late-loading logo could in principle shift the list under a landed scroll. Probed
with the HTTP cache disabled: the settled landing is identical to the warm run.
`loading="eager"`/`decoding="sync"` plus the hook's `requestAnimationFrame`
deferral means layout is settled before the scroll lands. Left as-is rather than
reserving a fixed lockup height, which would change every show's lockup seating.
