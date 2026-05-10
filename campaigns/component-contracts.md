---
status: in-progress
started: 2026-04
last_updated: 2026-05-10
---
# Component contracts via typed structs

## Goal

Every LiveView function component declares a typed contract for
domain-data attrs. The acceptable shapes are:

1. **Co-located view-model struct** with `@enforce_keys`
   (Phase 1 pattern — see
   `lib/media_centarr_web/components/continue_watching_row.ex`
   for the canonical example).
2. **Existing Ecto schema** referenced directly:
   `attr :entity, MediaCentarr.Library.Movie`.
3. **Top-level shared view-model** under
   `MediaCentarrWeb.ViewModels.*` when the same shape is
   consumed by multiple sibling components.
4. **`:any` / `:map` / `:list` ONLY with an explicit `doc:`
   justification** — Phoenix Streams (`:streams, :any`),
   Earmark AST nodes, transient state flags. Must not be the
   default.

## Status

Migration in progress. Several components have been migrated to
`@enforce_keys` Item structs (verified: `continue_watching_row`,
`poster_row`, `hero_card`, `coming_up_marquee`, `upcoming_cards`,
`track_modal`, `detail/facet`). Bare `:any` / `:map` / `:list`
attrs without justification still exist in `core_components.ex`
and elsewhere — sample greps surface ~10 in `core_components.ex`
plus `detail/more_info_panel.ex`,
`acquisition/queue_status_badge.ex`, etc.

> **Reconciliation needed on next pickup.** The seed memory
> referenced an external migration plan at
> `~/src/media-centarr/component-contract-plan.md` and a phase
> tracker (Phase 1 shipped in v0.27.4; phases 2–7 pending).
> That plan file no longer exists. First action when resuming:
> grep `attr :.*, :\(map\|list\|any\)` across
> `lib/media_centarr_web/components/` and
> `lib/media_centarr_web/live/`, build the current outstanding
> list, and rewrite the Workstreams + Status here. The phases
> below are placeholders inferred from the original plan —
> verify before treating as accurate.

## Decisions made

Append-only.

* `2026-04` — **Typed contract is the default, untyped is the
  exception.** Bare `:any` / `:map` / `:list` requires a
  `doc:` justification in the attr declaration.
* `2026-04` — **Three acceptable typed shapes**: co-located
  Item struct with `@enforce_keys`, existing Ecto schema
  reference, or shared `MediaCentarrWeb.ViewModels.*` for
  multi-component shapes.
* `2026-04` — **Triggering incident**: home-page row cards
  (Continue Watching, Coming Up, Recently Added) shipped as
  bare `<div>` elements with no link/click handler. The bug
  survived four layers of tests because every component took
  `attr :items, :list, required: true` and Logic tests
  asserted shape but never `:url`. Fix: Item structs with
  `@enforce_keys` so missing fields crash at struct
  construction (in Logic, where they're testable).
* `2026-04` — **Phase 7 introduces a custom Credo check
  (`TypedComponentAttrs`)** that flags new untyped attrs
  without a waiver. Until that lands, code review enforces.
* `2026-04` — **Tests for typed components**:
  `assert_raise ArgumentError, fn -> struct!(Item, %{...}) end`
  to lock the contract; `render_click` integration tests for
  any clickable surface; never assert on rendered HTML
  markup (per the project's `automated-testing` skill).

## Workstreams

The phase numbers below are inherited from the original
external plan and should be treated as approximate until
reconciled against the current code.

### A. Migrate remaining domain-data components

* [ ] Audit current state: grep
  `attr :.*, :\(map\|list\|any\)` across
  `lib/media_centarr_web/components/` and
  `lib/media_centarr_web/live/`, classify each match as
  *needs typed contract* vs *justified raw type with `doc:`*.
* [ ] Migrate domain-data attrs to one of the three typed
  shapes, in priority order:
  * Top-of-page surfaces (Library cards, detail page rows)
  * Modals (TrackModal pattern is already typed; align
    siblings).
  * Composite cards (PosterCard, HeroCard already typed;
    confirm).
* [ ] For each migrated component, add a Logic test that
  exercises the struct contract.

### B. `core_components.ex` cleanup

`core_components.ex` is the largest single source of bare
`:any` / `:map` / `:list` attrs. Many are legitimate
infrastructure (`:rest` slot, `:class` overrides) but each
needs a `doc:` to confirm intent rather than oversight.

* [ ] Walk every untyped attr in `core_components.ex`.
* [ ] Add `doc:` justification or migrate to a typed shape.

### C. Custom Credo check (`TypedComponentAttrs`)

* [ ] Implement under `credo_checks/`.
* [ ] Rule: `attr ..., :any | :map | :list` without `doc:`
  fails strict.
* [ ] Add waiver mechanism (allowlist module) for the small
  set of legitimate cases that can't justify per-attr.
* [ ] Wire into `.credo.exs` and run `mix credo --strict`
  green before shipping.

### D. Storybook stories with typed inputs

* [ ] Stories for typed components must use the actual
  struct, not raw maps — catches "story passes a map that
  doesn't match the struct" drift.

## Completion criteria

* Zero domain-data attrs typed `:any` / `:map` / `:list`
  without an explicit `doc:` justification, anywhere under
  `lib/media_centarr_web/`.
* `mix credo --strict` includes `TypedComponentAttrs` and
  passes.
* Every typed component has a Logic test asserting the
  struct contract.
* Storybook stories construct typed inputs via their structs,
  not raw maps.

## Out of scope

* Page redistribution / IA refactor — separate campaign.
* Data-layer projections — desktop-rearchitecture campaign.
* `:rest` and `:global` attrs — Phoenix-supplied infrastructure
  types, not domain data; the rule does not apply.

## Pointers

* `lib/media_centarr_web/components/continue_watching_row.ex`
  — Phase 1 canonical example (typed Item struct with
  `@enforce_keys`).
* `lib/media_centarr_web/components/poster_row.ex`,
  `hero_card.ex`, `coming_up_marquee.ex`, `upcoming_cards.ex`,
  `track_modal.ex`, `detail/facet.ex` — additional migrated
  components verified to use `@enforce_keys`.
* `lib/media_centarr_web/components/core_components.ex` —
  largest remaining untyped surface (Workstream B).
* `credo_checks/` — destination for `TypedComponentAttrs`
  (Workstream C).
* `automated-testing` skill in `.claude/skills/` — testing
  rules for typed components.
* The user-local memory entry
  (`feedback-component-contracts.md`) was the seed for this
  file. The external plan at
  `~/src/media-centarr/component-contract-plan.md` referenced
  by the memory no longer exists; rebuild the outstanding-work
  list from a current grep on next pickup.
