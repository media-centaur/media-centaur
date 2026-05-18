---
status: shipped
started: 2026-04
last_updated: 2026-05-18
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

**Shipped.** Reconciliation on 2026-05-18 walked the codebase
and found every workstream complete. The prior campaign file
was significantly out of date (it described "many bare attrs in
`core_components.ex` and elsewhere"); the actual state is:

* **165 total** `:map | :list | :any` attrs across
  `lib/media_centarr_web/{components,live}`.
* **157 (95%)** carry a `doc:` justification.
* **8 bare attrs remain** (`core_components.ex` ×7,
  `layouts.ex` ×1) — all Phoenix-supplied infrastructure
  (`:class`, `:id`, `:name`, `:value`, `:errors`, `:rows`,
  `:socket`) explicitly excluded by `MC0008`.
* **`MC0008 TypedComponentAttrs`** check is implemented at
  `credo_checks/typed_component_attrs.ex`, wired into
  `.credo.exs:192`, and passes `mix credo --strict` clean.
* **`MC0009 StorybookCoverage`** enforces a story per function
  component; storybook compile/render tests would catch any
  story passing a raw map to an `@enforce_keys` struct attr.

The combination of MC0008 (typed-or-documented attrs) +
MC0009 (story per component) + `storybook_render_test`
(stories must construct) provides three reinforcing layers
that hold the contract in place going forward.

## Workstreams (final state)

### A. Migrate remaining domain-data components ✅

Every component carrying domain data either uses a typed
shape (struct / Ecto schema / shared ViewModel) or carries a
`doc:` justification. Verified migrated components include:
`continue_watching_row`, `poster_row`, `hero_card`,
`coming_up_marquee`, `upcoming_cards`, `track_modal`,
`detail/facet`, `modal_shell`, `detail_panel` family,
`acquisition/*`, `library_cards`, `setup_steps`. The bare
attrs found in the earlier scan all reside in files explicitly
excluded by the Credo check.

### B. `core_components.ex` cleanup ✅ (descoped)

The 8 remaining bare attrs in `core_components.ex` +
`layouts.ex` are Phoenix-supplied generic infrastructure
(`:class`, `:rest`, form scaffolding). They are explicitly
excluded by `MC0008.excluded_file?/1` and match the
campaign's own "Out of scope" rule ("Phoenix-supplied
infrastructure types, not domain data; the rule does not
apply"). Listing them as a workstream was always a mistake;
the Credo check codifies the exclusion.

### C. Custom Credo check (`TypedComponentAttrs`) ✅

Shipped as `MC0008` at
`credo_checks/typed_component_attrs.ex`. Rule: any
`attr ..., :list | :map | :any | :global` under
`lib/media_centarr_web/` must carry a non-empty `doc:` field.
Recognises raw strings, string interpolation,
concatenation, sigils (`~s` / `~S`), and module-attribute
references (`doc: @doc_some_shape`) as valid waivers.
Excludes `core_components.ex` and `layouts.ex` as
Phoenix-supplied bases. Wired in `.credo.exs:192`; passes
strict.

### D. Storybook stories with typed inputs ✅

Stories for typed components construct their attribute
fixtures via the actual struct (verified spot-check:
`storybook/detail/more_info_panel.story.exs` uses
`%MediaCentarr.Library.Person{}` for `cast`/`crew`).
Where the component attr is a justified `:map` (polymorphic
Library entity), the story passes a literal map and that's
consistent with the contract. Any drift would crash
`storybook_render_test` at struct construction, so the test
suite enforces the contract structurally.

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
* `2026-05-18` — **Closure**: MC0008 + MC0009 +
  `storybook_render_test` form a 3-layer guard that prevents
  regression. Further per-component migration adds no marginal
  value — what isn't typed today is either documented or
  excluded infra. Workstream B's "8 bare attrs in
  core_components.ex" was always misclassified — those are
  out-of-scope infrastructure.

## Completion criteria (final)

* ✅ Zero domain-data attrs typed `:any` / `:map` / `:list`
  without `doc:` outside the excluded Phoenix-base files.
* ✅ `mix credo --strict` includes `TypedComponentAttrs`
  (MC0008) and passes.
* ✅ Every typed component has a Logic test asserting the
  struct contract (where applicable) — enforced by
  `storybook_render_test` constructing the struct.
* ✅ Storybook stories construct typed inputs via their
  structs.

## Out of scope (final)

* Page redistribution / IA refactor — separate campaign
  (now `campaigns/done/page-redistribution.md`).
* Data-layer projections — desktop-rearchitecture campaign.
* `:rest` and `:global` attrs — Phoenix-supplied
  infrastructure types, not domain data; codified in
  `MC0008.excluded_file?/1`.

## Pointers (final)

* `credo_checks/typed_component_attrs.ex` — `MC0008`,
  enforces the rule.
* `.credo.exs:192` — wiring.
* `credo_checks/storybook_coverage.ex` — `MC0009`, requires
  a story per function component (complements MC0008 by
  forcing stories to exercise the struct).
* `lib/media_centarr_web/components/continue_watching_row.ex`
  — canonical typed `Item` struct with `@enforce_keys`.
* `lib/media_centarr_web/components/modal_shell.ex` — example
  of justified `:map` attrs for a polymorphic shape, each
  carrying a `doc:` pointer to the producer.
