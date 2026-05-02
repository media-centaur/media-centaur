# Storybook Flesh-Out — Design Spec

**Date:** 2026-05-02
**Status:** Approved (brainstorming complete)
**Owner:** Shawn McCool

## Goal

Turn Phoenix Storybook from a thin scaffold (one full story, six stubs, one welcome page) into a structured, comprehensive, coherent component catalog with a thin design-system foundation. Long-term direction-of-travel: storybook becomes the canonical source for everything visual; skill files keep prose (decision-making, anti-patterns, when-to-use).

## Scope

### In scope

- Refresh `docs/storybook.md` triage table for every component currently in `lib/media_centarr_web/components/**`.
- Stories for every component flagged `:covered` or `:pending`, brought to a shared definition-of-done.
- Four `:page` stories under `storybook/foundations/`: colors, typography, spacing, UIDR index.
- New custom Credo check (`MediaCentarr.Credo.Checks.StorybookCoverage`) enforcing v1 (coverage) + v2 (story shape).
- Module-attribute convention (`@storybook_status`, `@storybook_reason`) on component modules.

### Out of scope

- Recipes as `:page` stories (stay in `user-interface` skill).
- Per-area landing pages (defer until Phase 5 done; revisit then).
- Motion documentation pages.
- Migration of `user-interface` skill content into storybook (long-term aspiration only).
- v3 of the Credo check (variant parity).
- Stories for `console_components`, `coming_up_marquee`, `continue_watching_row`, `track_modal` (permanently `:skip`).
- LiveView pages (covered by smoke tests + screenshot tour).

## Definition of Done (per-story rubric)

A "complete" component story shows:

1. **All variants** — every value of every enum-style attr. Generated via comprehension over `~w(...)` so the matrix can't drift from `attr :variant, :string, values: [...]`.
2. **All sizes/shapes** — each axis as its own `VariationGroup`.
3. **Required states** — loading, empty, error, loaded for any data-driven component. Disabled / active / focus where applicable.
4. **Edge cases** — long titles, missing artwork, near-0% / near-100% progress, very-long lists, single-item lists.
5. **Slots / `:let`** — at least one variation exercises a non-trivial slot for components that use slots.

Structural requirements:

- `def render_source, do: :function` (component stories).
- Module is `MediaCentarrWeb.Storybook.*`.
- `description` on each `Variation` / `VariationGroup`.
- Fixture data is **literal** in the story file (no `test/support/` factories), generic placeholders only (no real show titles per CLAUDE.md).

`storybook/core_components/button.story.exs` is the canonical example.

## Component-status convention

Every component module under `lib/media_centarr_web/components/**` declares its storybook status as a module attribute, co-located with the component:

```elixir
defmodule MediaCentarrWeb.ConsoleComponents do
  @storybook_status :skip
  @storybook_reason "Log stream is sticky LiveView state — covered by page smoke test"
  ...
end
```

Statuses:

| Status | Meaning | Reason required? |
|--------|---------|------------------|
| `:covered` | A story file exists at `storybook/<area>/<component>.story.exs` (implicit — no attribute needed). | n/a |
| `:pending` | A story is planned but not yet written. Treated as a soft warning by the Credo check. | Yes |
| `:static_example` | Component depends on context state in ways that prevent live storying; a static visual specimen will be added. | Yes |
| `:skip` | Component will never have a story. | Yes |

Convention: omit the attribute entirely once a story exists. Source-of-truth lives next to the code.

## Credo check — `StorybookCoverage`

New file: `credo_checks/storybook_coverage.ex`. Runs as part of `mix precommit` via `.credo.exs`.

### v1 — Coverage

**Component detection.** For every `.ex` file under `lib/media_centarr_web/components/**`, walk the AST and count *function components* — `def name(assigns)` (or `def name(assigns) when …`) preceded by at least one `attr` declaration in the same module scope. Files with zero function components (pure helpers, view-model structs like `detail/facet.ex`, JS shim modules) are skipped entirely.

**Coverage rule.** For each detected function component named `<func>` in module `<Mod>`:

1. If a story file exists at `storybook/<area>/<func>.story.exs` (where `<area>` is the module's bottom-segment snake-cased) → pass.
2. Else if `@storybook_status` is `:skip` or `:static_example` with non-empty `@storybook_reason` → pass. The attribute applies to **all** function components in the module unless a per-function override is added (deferred — for now the module-level skip is enough; multi-component modules with mixed coverage are an edge case to revisit if it occurs).
3. Else if `@storybook_status` is `:pending` with non-empty `@storybook_reason` → warning (does not fail precommit).
4. Else → error.

**Multi-component files.** `library_cards.ex` exports `poster_card`, `cw_card`, `toolbar` — each gets its own story file under `storybook/library_cards/`. Same convention as `core_components/` (one file per `<.button>`, `<.icon>`, etc.), already established by the seed stories.

### v2 — Story shape

For every `storybook/**/*.story.exs`:

1. Module name must start with `MediaCentarrWeb.Storybook.` → else error.
2. If `use PhoenixStorybook.Story, :component` → must define `function/0` → else error.
3. If `use PhoenixStorybook.Story, :component` → `def render_source, do: :function` must be present (or absent and using the default we configure globally) → else error.

### v3 (deferred)

Variant-parity check between component `attr :name, _, values: [...]` declarations and story coverage. Not built. Revisit after Phase 5.

### Implementation notes

- Pattern off `credo_checks/typed_component_attrs.ex` for AST traversal shape.
- Use `Credo.Code.prewalk` to find `attr ` calls, `defmodule` heads, `@storybook_status` / `@storybook_reason` module attributes, and `def function` / `def render_source` callbacks.
- File-existence check via `File.exists?/1` against the deduced story path.
- Tests live in `test/credo_checks/storybook_coverage_test.exs` (co-located with the existing pattern).

## Foundation pages (Phase 3)

Four `:page` stories under `storybook/foundations/` plus an index file:

```
storybook/foundations/
├── _foundations.index.exs
├── colors.story.exs
├── typography.story.exs
├── spacing.story.exs
└── uidr_index.story.exs
```

Each is `use PhoenixStorybook.Story, :page` with a `render(assigns)` returning HEEx. Module names: `MediaCentarrWeb.Storybook.Foundations.{Colors,Typography,Spacing,UidrIndex}`.

### `colors.story.exs`

- daisyUI semantic tokens as swatches: `bg-primary`, `bg-secondary`, `bg-info`, `bg-success`, `bg-warning`, `bg-error`, `bg-neutral`, `bg-base-100..300`.
- Each swatch shows: hex value, recommended `text-*-content` partner, one-line "use for X" rule.
- Surface treatments section: `body.media-centarr` gradient, `.glass-surface`, focus-ring rules under `[data-input=keyboard]`/`[data-input=gamepad]`.

### `typography.story.exs`

- Heading scale (h1–h6) with tracking, weight, and the Tailwind class shown beside each.
- Body text styles, caption, the font-family split (display vs sans, if any).
- Live samples in each style.

### `spacing.story.exs`

- Tailwind spacing scale visualized as boxes (1, 2, 4, 6, 8, 12, 16, 24…).
- Glass surface example with the actual `.glass-surface` class.
- Hover-scale and focus-ring rules demonstrated on a sample card.

### `uidr_index.story.exs`

- Numbered list of every UIDR rule with title and one-line description.
- Each entry links to the component story implementing it (`/storybook/<area>/<component>`).
- Entry-point a designer or new contributor lands on first.

## Phases (sequencing)

### Phase 1 — Map and enforce

1. Walk every component file in `lib/media_centarr_web/components/**`.
2. Refresh the triage table in `docs/storybook.md` with all current components.
3. Add `@storybook_status` + `@storybook_reason` attributes to every component without a story.
4. Build `MediaCentarr.Credo.Checks.StorybookCoverage` (v1 + v2).
5. Wire it into `.credo.exs`.
6. Add the `@storybook_status` convention to the `storybook` skill.

**Exit criteria:** `mix precommit` passes. Every component is either `:covered`, `:pending`, `:static_example`, or `:skip` — no implicit gaps.

### Phase 2 — Primitive depth

Bring existing stubs to the rubric bar:

- `input.story.exs` — every input type, error/no-error, label/help-text, disabled.
- `list.story.exs` — empty / single-item / many-items.
- `header.story.exs` — with/without subtitle, with/without actions slot.
- Deepen `flash.story.exs` — every `kind`, hidden/visible, with/without title.
- Deepen `table.story.exs` — empty / loaded / long-row / no-actions / with-actions.

**Exit criteria:** all six core_components stories meet the rubric.

### Phase 3 — Foundation pages

Implement the four `:page` stories above. Update `docs/storybook.md` with a "Foundations" section pointing at them.

**Exit criteria:** `/storybook/foundations/uidr_index` is the design-system entry point; the other three pages are linked from it.

### Phase 4 — Self-contained composites

Components without contract debt, one PR each:

- `modal_shell`
- `hero_card`
- `detail/facet_strip` (consumes `Detail.Facet` view-model structs)
- `detail/metadata_row`
- `detail/play_card`
- `detail/section`
- `detail/hero`

`detail/facet.ex` and `detail/logic.ex` are **not** function components (the former is a typed view-model struct + constructors, the latter is pure helpers) — they're declared `:skip` in Phase 1 with reasons stating so.

For each component: contract review (does it need typed-attr cleanup?) → story → precommit clean.

**Exit criteria:** all seven stories at rubric bar.

### Phase 5 — Contract-driven cards

One PR per component, in this order:

1. `poster_card` (canonical contract example — flagged in original triage)
2. `cw_card`
3. `toolbar`
4. `poster_row`
5. `upcoming_cards`
6. `detail_panel`

Per component: write the story, hit the contract smell, fix the contract, ship both in one PR. No batching.

**Exit criteria:** all six stories at rubric bar; component-contract-plan retired or near-retired for these components.

## Governance

Three reinforcing layers:

1. **Credo check** — hard gate, runs in `mix precommit`.
2. **Storybook skill** — agent-readable spec of the rule the Credo check enforces. Same-unit-of-work rule stays.
3. **Triage table** — living index in `docs/storybook.md`, regenerated/audited at the end of each phase.

No GitHub Action, no separate CI step, no manifest file.

## Open questions

None. All decisions made during brainstorming.

## References

- `.claude/skills/storybook/SKILL.md` — adding-a-story checklist, anti-patterns, story-type reference.
- `docs/storybook.md` — philosophy (eight rules), current triage table, pitfalls.
- `credo_checks/typed_component_attrs.ex` — AST traversal pattern to copy.
- `storybook/core_components/button.story.exs` — canonical story shape.
- `~/src/media-centarr/component-contract-plan.md` — typed-attr / ViewModel migration this initiative interlocks with.
