# Cour-aware acquisition — design

**Date:** 2026-06-22
**Status:** Approved (design); implementation pending

## Problem

A TV pursuit can silently never complete when a show's TMDB "season"
spans multiple broadcast runs (cours) but the release world packages
them separately.

Observed case: *Frieren: Beyond Journey's End* (TMDB 209867). TMDB
numbers the show as a single Season 1 of 38 episodes across three
cours:

| Cour | Episodes | Aired |
|------|----------|-------|
| 1 | E1–E16 | 2023-09-29 → 2023-12-22 |
| 2 | E17–E28 | 2024-01-05 → 2024-03-22 |
| 3 | E29–E38 | 2026-01-16 → 2026-03-27 |

Release-tracking correctly wanted the third-cour episodes (E29–E38,
`provenance: :calendar`). The acquisition path searched
`"Frieren Season 1"` and matched a
`Season 01 [2023-2024] COMPLETE 1080p BDRip` pack. That pack physically
contains only E1–E28 (it was encoded before the third cour aired), so:

- the download completed (`content_path` + `torrent_hash` captured),
- the reconciler found no files for E29–E38,
- the 10 units stayed `active`, pointing at an already-`acquired`
  target, and
- the pursuit can neither complete nor re-search. Permanently wedged.

Root cause: a season pack was credited with covering the full TMDB
season range without checking that the release could actually contain
those episodes. TMDB folds cours into one continuous season; scene
packs label the first run "Season 01 COMPLETE." The two disagree about
what "Season 1" means.

## Core idea

Every episode already carries an `air_date` (we fetch it for
release-tracking wants). From those dates alone we can segment a show
into **broadcast runs** (cours): contiguous episode ranges separated by
a long air-date gap. That single derived fact drives two fixes — one
defensive (stop matching impossible packs), one active (search the
right way for a later run).

No new persistence: runs are recomputed on demand from data we already
hold, consistent with the project's deriver model.

## Components

### 1. `Acquisition.CourSegmentation` (new, pure)

- **Input:** episodes/wants as `[{season, episode, air_date}]`, plus a
  `gap_days` threshold.
- **Output:** ordered runs, each `{index, first_ep, last_ep,
  date_span}`.
- **Algorithm:** sort in episode order; start a new run when the gap to
  the next episode's `air_date` exceeds `gap_days`.
- **Threshold:** a named module constant (e.g. `@default_gap_days 56`,
  8 weeks) — not a runtime Settings entry. Easy to tune in one place;
  no UI, no persistence. Keeps back-to-back split-cours together
  (Frieren's 2-week new-year break E16→E17 stays one run) while
  splitting genuine production gaps. For Frieren this yields
  **{E1–28: 2023–2024}** and **{E29–38: 2026}** — the boundary that
  matters for pack matching. The module stays pure: `gap_days` is a
  parameter defaulting to the constant, so tests can pass their own.
- Episodes with `nil` air_date attach to the current run (no split on
  missing data).

### 2. Coverage guard (extend the plan runner's pre-solve filter)

- **Rule:** a release cannot contain an episode that aired after the
  release was published. Compare candidate `SearchResult.publish_date`
  against each want's `air_date`; trim units that aired after publish
  from the release's coverage.
- Home: the plan runner's existing pre-solve filtering pass (the
  `Planner` moduledoc already delegates show-identity and exclusion
  filtering there; `Planner` itself stays pure).
- **Monotonic opt-in**, mirroring the existing fit-gate: `publish_date`
  nil → no guard (don't block on missing data).
- Effect: the 2024 pack stops being credited with the 2026 units, so
  the planner reports them `unfound` instead of falsely satisfied. This
  alone kills the silent never-completes failure, and it is general
  (not Frieren-specific).

### 3. Cour-aware query generation (extend `QueryBuilder` / recipe→criteria)

- When the residual units belong to a *later* run (not run 1), the
  `"{title} Season {n}"` query is wrong — it surfaces the first-run
  pack. Emit run-appropriate queries instead, ordered best-to-worst:
  - absolute ranges/episodes — `Frieren 29-38`, `Frieren - 29`
  - ordinal-season guesses — `Frieren 2nd Season`, `Frieren Season 2`
  - TMDB-numbered — `Frieren S01E29`
- **Trigger:** segmentation reports multiple runs *and* the residual is
  in a later one. (The user's "if there possibly are multiple cours"
  gate.)

### 4. Surfacing (reuse existing offer / decision-card path)

- Cour-search candidates are presented for the user to confirm, never
  auto-grabbed. The planner already has the "offer" concept and the
  decision card. Later-cour scene naming is fuzzy enough that a human
  stays in the loop.

### 5. TMDB episode-group enrichment (optional, last)

- Add `TMDB.Client.episode_groups/1` + `episode_group/1`. When a
  "Cours"/"Parts" group exists (Frieren has one: type 7, 3 groups),
  use it to *label* runs ("Cour 3") and improve query naming. Strictly
  opportunistic — air-date inference is always the base, since episode
  groups are opt-in per show and not guaranteed present.

## Phasing

- **Phase 1** — `CourSegmentation` + coverage guard. Stops the bug
  class on its own.
- **Phase 2** — cour-aware queries + surfacing for later-run residuals.
- **Phase 3 (optional)** — episode-group enrichment.

## Testing

- Pure modules (`CourSegmentation`, query generation) get unit tests
  with **synthetic** air dates and generic placeholder titles (house
  rule — no real titles in tests).
- Plan-runner integration test: a pack published before a want's
  air_date is trimmed → residual returns `unfound`, not satisfied.
- Query test: a later-run residual emits absolute/ordinal queries, not
  `Season N`.

## Out of scope / separate

- The existing wedged Frieren pursuit is not unstuck by this design
  (which prevents *new* bad matches). Cancelling it is a separate
  one-line operational step.
- Re-segmenting TMDB seasons in the library data model. We infer runs
  for acquisition only; the library still mirrors TMDB's season
  numbering.
