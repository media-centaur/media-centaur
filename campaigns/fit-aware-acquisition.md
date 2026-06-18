---
status: shipped v0.99.2 — deferred items + 75% default validation remain
started: 2026-06-18
last_updated: 2026-06-18
---
# Fit-aware acquisition (don't grab a whole series for one episode)

## Goal

Picking one episode of a show in media search grabbed the **whole
series**. Make the planner size its grabs to what the user actually
wants: a season/series pack only when you want most of what it
contains, individual episodes otherwise, and — when the only thing
covering an episode is an over-broad pack — surface that pack as an
explicit one-click *offer* rather than auto-grabbing it.

## Status

**Shipped in v0.99.2.** Fit gating in `Planner` + `RunPlan`, `span_sizes`
persisted on the plan, `pack_min_fit` setting (default 75%), and the
pack-offer surface on the plan board. Full `mix precommit` green (5083
Elixir + 547 bun tests). The `earmark` deps.audit blocker was resolved
with a documented ignore (the advisory is unreachable — parser-only,
trusted content). Remaining: validate the 75% default in real use, and
the deferred items below.

## Decisions made

* `2026-06-18` — Root cause is the planner/descent, not selection: one
  episode makes a correct one-unit plan, but the broad-to-narrow descent
  halts on the first covering pack and `Planner` consolidated by breadth
  with **no over-download penalty**, so a series pack satisfied a lone
  episode before the episode term ever ran.
* `2026-06-18` — Fix = **fit gating**. `fit = wanted-in-span /
  total-aired-episodes-in-span`; a pack consolidates/assigns only when
  `fit ≥ pack_min_fit`. Owner chose **"most of the span," user-controllable**
  → setting `auto_grab.pack_min_fit`, default **75**.
* `2026-06-18` — When only an over-broad pack covers an unfound unit,
  **offer** it (explained CTA, reuses `choose_release`), never auto-grab.
  Owner chose "offer it, explaining the situation."
* `2026-06-18` — Gating is **monotonic / opt-in**: active only when the
  plan carries `span_sizes` (per-season aired counts from the targeting
  selection). Movies + tracking drop plans have none → legacy broad-first
  untouched. Unknown span-total is never gated, so the rule can only ever
  *remove* a provably bad-fit pack. Episode spans gate by intrinsic breadth.
* `2026-06-18` — Existing planner/descent tests stayed green unchanged
  (their wants are the full aired span → fit 1.0); the Orville
  anti-fragmentation regression is untouched.

## Next steps

1. After living with it: validate the **75% default** — nudge if it feels
   too eager (grabs packs you didn't want) or too strict (too many singles).
2. Replace `earmark_parser` with a maintained markdown lib eventually
   (earmark is retired); then drop the deps.audit ignore in `mix.exs`.

## Completion criteria

* ~~Shipped to `main` + tagged.~~ Done — v0.99.2.
* ~~`earmark` blocker resolved so `mix precommit` is green.~~ Done —
  documented ignore (advisory unreachable).
* Owner has used it on a real sparse pick and confirmed it grabs the
  episode, not the series.

## Deferred / out of scope

* **Tracking drop plans don't get fit-gating** (they carry no
  `span_sizes`) — deliberate, to avoid changing automated behavior
  unexpectedly. Wire span sizes through `ReleaseTracking` → the drop
  planner later if over-grab shows up there too.
* The offer surfaces one pack per unfound group; richer "here are the 2
  packs that would cover these gaps" consolidation not attempted.

## Pointers

* `lib/media_centaur/acquisition/planner.ex` — fit gating, `best offer`.
* `lib/media_centaur/acquisition/jobs/run_plan.ex` — descent, prefs,
  offer write-back.
* `lib/media_centaur/acquisition/targeting.ex` — `aired_counts/1` (fit denominator).
* `lib/media_centaur/acquisition/auto_grab_settings.ex` — `pack_min_fit`.
* `lib/media_centaur/acquisition/view_models/plan_board.ex` — `Offer`.
* `priv/repo/migrations/20260618090000_add_plan_fit_fields.exs`.
* Memory: [[project-fit-aware-planner]].
