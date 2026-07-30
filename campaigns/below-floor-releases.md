---
status: planning
started: 2026-07-30
last_updated: 2026-07-30
---
# Below-floor releases — surface them properly

## Goal

When every findable release of a title sits below the user's quality
floor, the plan board says "unfound" — indistinguishable from "this
title does not exist on your indexers." Design (then build) a proper
surface for below-floor availability, so the user sees *what exists*
and can decide, instead of a dead end that reads like a search failure.

## Status

Planning — the design conversation has not started. This file exists to
carry the diagnosis context into it. **Do not design bottom-up from the
current code**; the owner wants to lead the design session fresh.

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

## Open questions for the design session

1. Scope: movies only (the diagnosed gap) or unify with TV episode
   below-floor drops?
2. Where does it surface — plan-unit offer on the board (like pack
   offers), the expectation panel, or something else?
3. Is "unknown quality" (no resolution token, e.g. the unlabeled AMZN
   WEB-DL) presented the same as "known below floor" (720p)?
4. Does accepting a below-floor release record intent — e.g. mark the
   unit for a future upgrade sweep (touches the deferred auto-upgrade
   ideas in `playable-item-versions.md`), or is it a plain grab?
5. Does the quality ladder need a sub-1080p tier to *rank* below-floor
   candidates, or is nil-quality + size/seeders enough to present them?
6. Wording: "below your quality floor" vs "no acceptable release" — the
   guide/wiki vocabulary must not read as "not found".

## Decisions made

* `2026-07-30` — Campaign created from the *The Magician* diagnosis;
  no design decisions yet.

## Next steps

1. Owner-led design session (fresh context window) using this file as
   the brief; settle the open questions above.
2. Record the settled shape here (and an ADR if it changes planner
   policy repo-wide), then plan implementation phases.

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
