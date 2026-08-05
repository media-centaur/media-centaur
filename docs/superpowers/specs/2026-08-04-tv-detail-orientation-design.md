# TV Detail Orientation — Design

*2026-08-04 · status: direction approved via mockups (`mockups/detail-orientation/7-marquee-quiet`, gitignored — keep until implemented)*

> **Revised again 2026-08-05 — see
> [TV Modal Auto-Orient](2026-08-05-tv-modal-auto-orient-design.md).** The
> "All seasons collapsed by default" and "Auto-scroll" sections below no
> longer hold: once the orientation block became sticky, opening mid-list
> stopped costing the hero, so the season holding the next episode opens
> expanded and the document opens scrolled to that episode. Everything else
> here still stands.

> **Revised 2026-08-05 after live use.** The marquee + subline block
> described below was shipped, then removed as redundant: the Play
> button's own label already names the next episode, and the subline's
> runtime/series-percent read as noise. What survives of the hero
> orientation is the **season hairline** (full for a completed series)
> and the Play label; the description moved into the freed right
> column, and catalog facts (network / rating / genres / language)
> moved to the More info view. `ViewModel.Orientation` remains as the
> hairline's derivation. Sections below describe the original design.

## Problem

The TV series detail page auto-scrolls to the current episode
(`ScrollToResume` on `#detail-content`), so the *typical* view is the middle
of a long episode list: dim synopsis walls, no hero, none of the page's
design investment visible. The orientation the user actually wants is
quantitative — current season/episode, progress through the season, progress
through the series — not content preview (spoiler-free mode exists precisely
to avoid synopses). The full episode list is used rarely (rewatch picking,
manage), yet it is the body of the page.

## Design

The hero carries all orientation; the body shrinks to compact bookkeeping;
the auto-scroll dies for TV. The page always opens at the top, which is now
sufficient for the common case (orient + play).

### Hero orientation block (TV series only)

- **Marquee**: "Up next" overline + large `S4 · E10` display type beside the
  play actions. Never shows the episode title, in any spoiler mode — it
  states position, not content.
- **Season hairline**: a 2px luminous progress line pinned to the hero
  backdrop's bottom edge; fill = watched/total episodes of the current
  season; primary blue with a soft glow.
- **Whisper subline** under the marquee, `/50` opacity, tabular-nums,
  `.text-on-image`: `21m · 9 of 22 this season · 49% of the series`.
  - Runtime segment omitted when the next episode's runtime is unknown.
  - Single-season series drop `· X% of the series` (season = series).
- **PlayCard progress row**: for TV series, the card's percent/remaining line
  is removed — the hero now states it. Movies/movie-series keep the current
  PlayCard unchanged.

All numbers derive from the existing `ProgressSummary` /
`LibraryProgress.resume_target_for/1` data; no new progress semantics.
Season 0/specials counting follows whatever those summaries already do.

**Edge states**

| State | Marquee | Hairline | Subline |
|---|---|---|---|
| Unstarted series | `S1 · E1`, overline "Start here" | empty | `22m · 21 episodes this season · 138 in the series` |
| Mid-episode resume | resume episode (unchanged playback semantics) | current-season fill | unchanged format |
| Series complete | overline "Series complete", no episode marquee | full | `138 episodes watched` |

### Body: compact accordion only

- **No series strip.** (A segmented per-season visualization was prototyped
  and rejected as noise — mockups 1, 4, 5, 6.)
- **All seasons collapsed by default.** `auto_expand_season` and its
  current-season default go away.
- **Season rows**: chevron · `Season N` · right-aligned meta
  (`21 episodes · Watched ✓` or `13 remaining`).
- **Expanded season** renders dense one-line episode rows:
  `10 · Title · 21m · ✓` — number, title (existing spoiler-blur rules for
  unwatched), runtime, watched check. The next-up row keeps its highlight
  (primary wash + inset left edge + "next" tag). Row click plays, as today.
- **Per-row disclosure** (small info affordance) expands an episode's
  synopsis + thumbnail inline for rewatch picking; spoiler rules unchanged.
- Extras section unchanged.

### Auto-scroll

`ScrollToResume` stays in `app.js` — movie-series rows still render
`data-resume-target` on load. TV stops triggering it structurally: collapsed
seasons render no target row, and the hook only scrolls on mount/entity
change, so expanding a season later cannot yank the viewport.

### Scope

TV series only. Movie and movie-series detail rendering is untouched; the
movie-series analog ("which film am I on") can adopt the marquee pattern in
a later change.

## Components and consequences

- `detail_panel.ex`: new hero-region function components (marquee +
  hairline + subline — named at plan time), dense `season_list` rows,
  `auto_expand_season` removal. The formatter for the subline/hairline is a
  pure function, unit-testable.
- **Storybook** (MC0009, storybook-first): stories for every new/changed
  function component land in the same change; edit story variations first as
  acceptance criteria.
- **Input system**: episode/season rows keep `data-nav-item`; verify
  keyboard/gamepad expansion of collapsed seasons and that focus lands
  sanely with the new default-collapsed state.
- **Tests** (test-first): unit tests for the orientation formatter
  (edge-state table above); LiveView tests for default-collapsed rendering,
  expand event, dense-row content, spoiler blur, next-up highlight, and no
  `data-resume-target` on initial TV render. Real-browser verification
  before claiming done.
- **Wiki**: update the *Using Media Centaur* browsing page (same unit of
  work).

## Rejected alternatives

- **Designed mid-scroll** (sticky condensed header, keep auto-scroll):
  fights the diagnosis — the list isn't where orientation lives.
- **Segmented series strip / interactive season journey map** (mockups 1,
  4, 5, 6): visually noisy, especially at 30 seasons; navigation-by-map bets
  on discoverability the accordion gives for free. Library reality today:
  17 series, max 8 seasons.
- **Episodes behind a separate view**: adds a click for rewatch/manage with
  no page-quality gain once the accordion collapses to ~7 rows.
