---
status: in progress
started: 2026-07-30
last_updated: 2026-07-31
---
# Below-floor releases — surface them properly

## Goal

When every findable release of a title sits below the user's quality
floor, the plan board says "unfound" — indistinguishable from "this
title does not exist on your indexers." Design (then build) a proper
surface for below-floor availability, so the user sees *what exists*
and can decide, instead of a dead end that reads like a search failure.

## Status

Phases 1+2 (movie offer path + board UI) implemented and verified
2026-07-31 (`3428ab0c`), including a live-browser check against the
real *The Magician* plan — 6 candidates offered with correct badges.
Unreleased. Next: Phase 3 (TV parity) or ship movies-first.

## Settled design (2026-07-31)

Below-floor becomes the **third instance of the planner's
"offer, never auto-grab" shape**, alongside fit-gated pack offers and
later-cour offers.

* **Trigger**: search yields ≥1 identity-matched release but zero
  acceptable ones → the unit records a below-floor offer carrying the
  candidate set, instead of a bare `unfound`. Zero identity-matched
  releases remains true `unfound`, untouched.
* **Surface**: distinct unit state on the plan board (chip), with a
  panel listing candidates — quality badge, size, seeders. Per-candidate
  grab routes through the existing user-pick path, which already
  bypasses the floor by explicit consent. UI polished as part of the
  build, not a follow-up pass.
* **Quality presentation**: known-below-floor (`720p`, `DVD`) and
  unknown-quality (`Quality unknown`, no resolution token) are visually
  distinct; both are offered.
* **Ranking**: no new quality-ladder tiers — candidates order by
  size/seeders within nil-quality.
* **Grab semantics**: a below-floor grab is a plain grab. Recording
  upgrade intent is deferred to `playable-item-versions.md`.
* **Scope**: unified design for movies and TV; movies build first, TV
  follows with the same offer shape (Phase 2).

### Approved copy

The word "floor" is **rejected** for user-facing copy — the user's
vocabulary is "quality preference" / "lower quality available".

* Chip: **Lower quality available**
* Panel heading: **Nothing matching your quality preference**
* Panel body: *Lower-quality releases are available. Grabbing one takes
  it for this title without changing your preference.*
* Badges: `720p` / `DVD` (known), `Quality unknown` (unlabeled)
* Grab verb: reuse whatever the existing release picker uses — no new
  verb.
* Antecedent check at implementation time: copy must use the true name
  of the quality setting as it appears in Settings; adjust "quality
  preference" if Settings names it differently.
* True-unfound wording stays as-is.

## The triggering case (2026-07-30)

*The Magician* (2005, small Australian indie), movie plan
`b872c4b6-4588-4dec-a41d-7810b1f6cf53`:

* The search chain worked: the `The Magician 2005` rung returned 62
  results, **6 of which are genuine releases of the film** and pass
  identity matching (2× 720p WEBRip, 2× DVDRip, 2× AMZN WEB-DL with no
  resolution token, ~1 GB).
* The quality ladder is deliberately two-tier (`Search.Quality`:
  `:uhd_4k` / `:hd_1080p` / `nil`; `acceptable?(nil, _, _) == false`),
  so all 6 were rejected and the unit went `unfound` with no trace.
* For this film a 1080p may never exist — the 720p WEBRip is plausibly
  the best there will ever be. The verdict was correct *by policy*; the
  presentation was the failure.

## What exists today (verified in code, 2026-07-30)

* **Movies have no offer path at all**: `RunPlan.run_movie` filters by
  red-flags → exclusions → `TitleMatcher.matches?` → `Quality.acceptable?`
  and reduces to one best pick or `nil` → bare `unfound_changeset`.
* **TV has offer machinery, but for a different axis**: fit-gated pack
  offers and later-cour offers (`offer_attrs`, the expectation panel)
  cover *scope*, not *quality* — below-floor TV episode releases vanish
  exactly like movie ones.
* **Workaround**: omnibox release mode → manual Prowlarr search → pick;
  a user-picked release bypasses title matching and the floor.
* Relevant precedent: the planner's philosophy is "offer, never
  auto-grab" for anything outside policy (fit-gated packs, later cours).
  Below-floor is plausibly a third instance of the same shape — but that
  is a starting hypothesis for the design session, not a decision.

## Open questions — all settled 2026-07-31

1. Scope → unified in design, movies first in build.
2. Surface → plan-unit offer (third "offer, never auto-grab" instance);
   polish the UI as we go.
3. Unknown quality vs known below floor → presented distinctly, both
   offered.
4. Upgrade intent on accept → deferred follow-up
   (`playable-item-versions.md`); MVP grab is plain.
5. Ladder tiers → no growth; nil-quality + size/seeders ranking.
6. Wording → approved copy above; "floor" rejected as user vocabulary.

## Decisions made

* `2026-07-30` — Campaign created from the *The Magician* diagnosis;
  no design decisions yet.
* `2026-07-31` — Design session held; all six open questions settled
  (see above). Below-floor is a planner offer, not a new policy — no
  ADR needed; this file is the record. Copy approved with "quality
  preference" vocabulary, "floor" rejected.

## Implementation phases

1. ✅ **Movie offer path** (`3428ab0c`): `run_movie` stamps
   `below_floor_count` on the unit (identity-verified, non-bait,
   non-excluded releases below the floor, deduped across rungs) when
   nothing acceptable exists; true unfound unchanged. The candidate
   *set* is NOT persisted — it's served live from the corpus via the
   existing swap picker (`alternatives_for/1`, which never
   floor-filters), so only the durable verdict is denormalized. A
   design refinement over the original "carrying the candidate set"
   wording: one representation, the corpus.
2. ✅ **Board + panel UI** (`3428ab0c`): `PlanBoard.BelowFloor` offer
   row (approved copy verbatim; such units are excluded from the bare
   `gaps` row), "Show them" opens the existing alternatives panel
   (release attr now optional — no exclude-current verb when nothing
   is assigned). Display-quality badges via new
   `Quality.display_label/1` (presentation-only parse: 720p/576p/480p/
   DVD; nil → "Quality unknown" ghost badge) — also upgraded the
   assignment/alternative labels generally. Story variations added.
3. **TV parity**: same offer shape for episode/unit below-floor drops
   (stamp counts in `solve_groups`/unfound path, chip on unfound cells,
   per-unit offer rows). Until this lands, the movie/TV asymmetry
   stands as recorded here.
4. **Ship**: wiki/guide update (vocabulary per approved copy — never
   reads as "not found"), CHANGELOG, tagged release.

### Noted during Phase 1 (deferred)

* Tracking drop plans that solve to zero found are deleted by the mode
  gate (`delete_tracking_draft`) — a below-floor verdict on a *tracked*
  movie never surfaces. Whether tracking should keep such drafts (or
  the want should carry the verdict) is a Phase 3+ question.
* Above-max-quality candidates (e.g. only 4K exists, max is 1080p) are
  not counted — "lower quality available" would be a lie. They stay a
  bare unfound; a separate "higher quality only" surface was not
  designed.

## Next steps

1. Phase 3 — TV parity (or ship movies-first and fold TV into the next
   release; owner's call at ship time).

## Completion criteria

* A plan whose title has only below-floor releases visibly says so and
  shows what exists — never a bare "unfound".
* The user can act on a below-floor candidate from that surface
  (whatever form the design settles on) without dropping to manual
  release-mode search.
* Movie and TV behavior are consistent, or the asymmetry is a recorded
  decision.
* Wiki/guide updated; shipped in a tagged release.

## Pointers

* `lib/media_centaur/acquisition/jobs/run_plan.ex` — `run_movie` (no
  offer path), `offer_attrs` (TV offer shape).
* `lib/media_centaur/search/quality.ex` — the two-tier ladder.
* `campaigns/playable-item-versions.md` — deferred auto-upgrade ideas
  that Q4 touches.
* Diagnosis session: 2026-07-30, following the search-robustness fixes
  (origin-country tags, year-as-disambiguator, apostrophe sanitization,
  canonical-year-anywhere — see `git log` around v0.105.2+).
