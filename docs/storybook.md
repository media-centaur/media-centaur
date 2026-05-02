# Phoenix Storybook

Internal contributor doc. The runnable companion to the [`user-interface`](../.claude/skills/user-interface/SKILL.md) skill — a live catalog of every function component rendered with the real theme, glass surfaces, and daisyUI variants.

> Mounted at <http://localhost:1080/storybook> in `:dev` only. Not exposed in `:prod`.

## Philosophy

Eight rules. Read them before adding a story or changing a component.

### 1. Components, not pages

Storybook catalogs **function components** — `<.button>`, `<.poster_card>`, `<.toolbar>`, `<.modal_shell>`, badge/header recipes. Full LiveViews stay covered by page smoke tests + the screenshot tour. They depend on PubSub, contexts, and the input system in ways that don't survive isolation; faking those dependencies turns the story into a lie.

### 2. Stories follow the component contract

Every variation is a struct/map literal mapped onto the component's typed `attr`s. If a component can't be storyboarded without faking an entire context, that's a smell about the component's contract — fix the contract, not the story. This is the reason the [component-contracts initiative](#) (typed attrs / ViewModel structs) and storybook reinforce each other.

### 3. Every meaningful state

A story isn't done if it shows only the happy path. Cover:

- **Loading / empty / error / loaded** for any data-driven component.
- **Variant × size × shape** for components with multiple axes (`<.button>` is the canonical example — see `storybook/core_components/button.story.exs`).
- **Edge cases the design has to handle** — long titles, missing artwork, in-progress percentages near 0% and 99%, paused vs playing states, etc.

Use `VariationGroup` to keep a matrix readable instead of one giant flat list.

### 4. Same unit of work as the component

A PR that adds or changes a component **must** update its story in the same change. No exceptions. This is the same rule we apply to wiki pages for user-visible changes — drift kills the value. Treat the story as part of the component's definition.

If a refactor splits one component into two, write the second story before merging.

### 5. Dev-only

Storybook is mounted under `if Mix.env() == :dev` in `MediaCentarrWeb.Router`. The dep itself is `only: [:dev, :test]` (test inclusion is required so the `import PhoenixStorybook.Router` inside the dev guard still passes compile in `:test` — see the comment in `mix.exs`). Same posture as Tidewave: never reachable in production.

### 6. Visuals only — no assertions, no logic

Storybook is the parallel design-system surface. **Don't** write logic-heavy assertions, snapshot diffs, or behavioural checks inside stories. That's [`automated-testing`](../.claude/skills/automated-testing/SKILL.md)'s job. A story is a visual specimen; if you find yourself writing logic, you're using the wrong tool.

### 7. Skill linkage

The [`user-interface`](../.claude/skills/user-interface/SKILL.md) skill describes recipes ("buttons have these variants, badges follow this rule"). Storybook is where you go to **see** them. When you add a recipe to the skill, link out to the relevant story. When you add a story, mention which UIDR it implements (e.g. `[UIDR-003]` for buttons).

### 8. Skip when it doesn't fit

Some components don't belong in storybook:

- **Sticky LiveView state** — components that depend on the LiveView's mount lifecycle (`@socket`-bound assigns, `handle_info`, PubSub subscriptions). Page smoke tests cover these.
- **`data-input` modes** — focus rings only render under `[data-input=keyboard]`/`[data-input=gamepad]`, set by the input system on `<html>`. A static example is fine; do not fake the input mode in a story.
- **Orchestration code** — anything that exists to coordinate between contexts rather than render a visual surface.

If unsure, ask: *would a designer or another contributor look at this in storybook to understand what it should look like?* If no, skip.

## Adding a new story

```text
storybook/<area>/<component>.story.exs
```

Module convention:

```elixir
defmodule MediaCentarrWeb.Storybook.<Area>.<Component> do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.<Area>.<component>/1
  def render_source, do: :function

  def variations do
    [...]
  end
end
```

**Boundary requirement.** All story modules must live under `MediaCentarrWeb.Storybook.*`. Anything outside that namespace falls outside the existing `MediaCentarrWeb` boundary and triggers a compile-time warning that fails `--warnings-as-errors`. The auto-generated default `Storybook.*` namespace is **wrong** for this repo — rename it.

Add an entry to the area's `_<area>.index.exs`:

```elixir
def entry("<component>"), do: [icon: {:fa, "<faicon>", :thin}]
```

If the area is new, create `_<area>.index.exs` defining a module `MediaCentarrWeb.Storybook.<Area>`.

## Variation patterns

| Pattern | When to use |
|---------|-------------|
| `%Variation{}` | A single illustrative state (e.g. disabled, error). |
| `%VariationGroup{}` | A matrix axis — every variant, every size, every state. Renders side-by-side with a description. |
| Comprehensions inside `variations/0` | Generate variation IDs from a list (`for variant <- ~w(...)`). Keeps the story length proportional to interesting axes, not boilerplate. |

The `<.button>` story (`storybook/core_components/button.story.exs`) is the seed example — copy its shape for new stories with multiple axes.

## Component triage

What belongs and what doesn't. Status mirrors the `@storybook_status` module attribute on each component module — when this table and the source disagree, the source is correct.

| Component | Status | Notes |
|-----------|--------|-------|
| `core_components.button/1` | ✅ covered | Seed story; full matrix |
| `core_components.icon/1` | ✅ covered | Sizes + colors + motion |
| `core_components.input/1` | ✅ covered | Each input type, error/no-error |
| `core_components.flash/1` | ✅ covered | Each level |
| `core_components.header/1` | ✅ covered | Header recipes |
| `core_components.list/1` | ✅ covered | Description list |
| `core_components.table/1` | ✅ covered | Empty/loaded/long-row states |
| `detail.facet_strip/1` | ⏳ pending | Phase 4 — facet row above metadata |
| `detail.hero/1` | ⏳ pending | Phase 4 — backdrop + title block |
| `detail.metadata_row/1` | ⏳ pending | Phase 4 — badge + items row |
| `detail.play_card/1` | ⏳ pending | Phase 4 — primary play CTA + progress |
| `detail.section/1` | ⏳ pending | Phase 4 — titled section wrapper |
| `hero_card/1` | ⏳ pending | Phase 4 — featured-item card |
| `modal_shell/1` | ⏳ pending | Phase 4 — open/closed (always-in-DOM pattern) |
| `detail_panel/1` | ⏳ pending | Phase 5 — many states (no artwork, no plot, episode list) |
| `library_cards.poster_card/1` | ⏳ pending | Phase 5 — exemplifies typed-attr/ViewModel value |
| `library_cards.storage_offline_banner/1` | ⏳ pending | Phase 5 — single summary string |
| `library_cards.toolbar/1` | ⏳ pending | Phase 5 — type tabs × sort × filter axes |
| `poster_row/1` | ⏳ pending | Phase 5 — horizontal item row |
| `upcoming_cards.upcoming_zone/1` | ⏳ pending | Phase 5 — calendar + active shows zone |
| `track_modal/1` | 🖼 static example | Depends on TMDB context |
| `coming_up_marquee/1` | ⚠️ skip | Depends on release-tracking timer state |
| `console_components.chip_row/1` | ⚠️ skip | Log stream is sticky LiveView state |
| `console_components.log_list/1` | ⚠️ skip | Log stream is sticky LiveView state |
| `console_components.journal_list/1` | ⚠️ skip | Log stream is sticky LiveView state |
| `console_components.source_tabs/1` | ⚠️ skip | Log stream is sticky LiveView state |
| `console_components.action_footer/1` | ⚠️ skip | Log stream is sticky LiveView state |
| `continue_watching_row/1` | ⚠️ skip | Depends on watch-history feed |
| `detail/facet.ex` | ⚠️ skip | Typed view-model struct, not a function component |
| `detail/logic.ex` | ⚠️ skip | Pure helpers, not a function component |
| `layouts.app/1`, `layouts.flash_group/1`, `layouts.console_mount/1` | ⚠️ skip | Page layouts, not catalog material |

Closing all "pending" rows is the definition of "the storybook is the design system."

## Pitfalls and gotchas

- **Tailwind v4 source globs.** `storybook/` is added to `assets/css/app.css` `@source` directives so utility classes inside variations compile. New top-level dirs need the same treatment.
- **Theme.** The storybook iframe loads our real `app.css` so the body gradient + glass surfaces work. Do not rely on a separate `storybook.css` — it was deleted on setup and should not return.
- **Boundary.** See "Boundary requirement" above. Story modules must be `MediaCentarrWeb.Storybook.*`.
- **Stateful components.** If a component depends on `data-input` modes or sticky LiveView state, write a static example illustrating the visual outcome — do not synthesize fake input state.
- **Fake data lives in the story.** Don't import factories from `test/support`; story fixtures should be obvious literals so a designer reading the story can reason about the rendered output.

## Routes

| URL | Purpose |
|-----|---------|
| `/storybook` | Root catalog |
| `/storybook/core_components/button` | Button variations |
| `/storybook/welcome` | Philosophy landing page (mirrors this doc) |

## See also

- [`user-interface`](../.claude/skills/user-interface/SKILL.md) skill — recipes and design values
- [`automated-testing`](../.claude/skills/automated-testing/SKILL.md) skill — what to test where
- [Phoenix Storybook docs](https://hexdocs.pm/phoenix_storybook) — variation/index reference
