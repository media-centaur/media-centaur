---
name: storybook
description: "Use this skill when adding or changing a function component, writing/editing a `*.story.exs` file, working in `storybook/`, mounting a new daisyUI variant, or answering questions about the component catalog. Triggers on `lib/media_centarr_web/components/**`, `storybook/**`, references to `Variation`/`VariationGroup`/`PhoenixStorybook`, or 'storybook'/'component catalog' in the user's message."
---

> Before writing or editing any story, **read this whole file**. The mistakes are easy to make and cheap to avoid: wrong module namespace breaks Boundary, wrong sandbox css breaks the chrome, wrong story type silently strips state. The references in `references/` cover the long-form deep dives.

## Triggers and the rule

```
existing component change → story variation FIRST → implement until it renders → wire into LV → mix precommit
new component → component + story in the same PR → mix precommit
```

A PR that adds or modifies a function component **must** add or update its story in the same change. Same rule we apply to wiki sync. Drift kills the value. **For existing components, the story edit comes BEFORE the component edit** — see *Storybook-first* below.

## Storybook-first for visual changes

When changing a function component **that already has a story**, edit the story *first* — not at the end. The catalog is the source of truth for visual states; if you implement in the LiveView first, stale variations silently keep "working" because they render the resting state instead of the new state, and the drift is invisible until the next person opens the story.

### Flow

1. **Open the story.** Add or modify the `%Variation{}` describing the desired end-state — including its `attributes` map with the new prop shapes.
2. **Implement the component** until that variation renders correctly at `/storybook/<area>/<component>`. Treat the variation as the acceptance criterion.
3. **Then** wire the new contract into the LiveView event handlers / templates.
4. `mix precommit` → push.

### Why

Story-first makes the catalog the gate: if the variation doesn't render the new state, the implementation isn't done. App-first lets the catalog rot silently because nothing forces you to look at it.

### When this rule does NOT apply

- **New component, no story yet.** Build the component, then add the story in the same PR.
- **Pure interaction change** (event-handler logic, debounce timing, optimistic updates) with no new visual state. Storybook only renders frozen states; it can't exercise click-once-then-click-twice. Add a variation per *state* in the interaction's machine (resting / pending / confirming), but the wiring still belongs in the LV.
- **App-level layout / composition** changes — moving a component between pages, reflowing a multi-component layout. Storybook isolates components; cross-component layout lives in page smoke tests and live testing.
- **Trivial one-line tweaks** (a color swap, a typo). Use judgement; if it doesn't change a prop shape or add a state, it doesn't need a story round-trip.

### Worked example — adding an inline-confirm pending state

**Wrong order (what bit us in v0.37.5):** edit `info_view`, add the `:all` pending render, push — *then* notice `storybook/detail_panel/detail_panel.story.exs` still has `delete_confirm: {:file, %{path:, name:, size:}}` from the old modal-payload contract, silently rendering the resting state because the new code's `==` match never hits the old shape.

**Right order:**
1. Open `storybook/detail_panel/detail_panel.story.exs`.
2. Replace the stale variation with `:delete_pending_all_inline` carrying `delete_confirm: :all`.
3. Run dev, navigate to the variation. It crashes or renders the resting state because the component doesn't handle `:all` yet.
4. Edit the component until the variation renders the desired pending state.
5. *Then* write the LiveView `delete_all_prompt` handler that produces `delete_confirm: :all`.

## Philosophy (eight rules)

Full long-form: [`docs/storybook.md`](../../docs/storybook.md). Abridged:

1. **Components, not pages.** Catalog `<.button>`, `<.poster_card>`, `<.modal_shell>`. Skip full LiveViews — page smoke tests cover them.
2. **Stories follow the contract.** Variations are struct/map literals matching typed `attr`s. If you can't story without faking context, fix the contract.
3. **Every meaningful state.** Loading / empty / error / loaded; variant × size × shape. Use `VariationGroup` for matrices.
4. **Same unit of work, story first.** Story updates ship in the same PR as the component change. For *existing* components, the story variation is edited *before* the component (see *Storybook-first* above).
5. **Dev-only.** Mounted under `if Mix.env() == :dev`. Dep is `only: [:dev, :test]`.
6. **Visuals only.** No assertions, no logic — that's `automated-testing`'s job.
7. **Skill linkage.** `user-interface` recipes link to stories; stories cite UIDR numbers.
8. **Skip when it doesn't fit.** Components needing `data-input` mode, sticky LiveView state, or PubSub — static example or no story.

## Project conventions (non-negotiable)

| Convention | Rule | Why |
|------------|------|-----|
| **Module namespace** | All story modules must be `MediaCentarrWeb.Storybook.*` | The `MediaCentarrWeb` boundary already covers this prefix. The default `Storybook.*` namespace from the generator falls outside any boundary and emits a `--warnings-as-errors` build failure. |
| **Sandbox class** | `sandbox_class: "media-centarr"` (already set in `lib/media_centarr_web/storybook.ex`) | The live app body also has `class="media-centarr"`. Our `body.media-centarr` gradient and `.glass-surface` rules apply consistently in both contexts. |
| **CSS path** | `css_path: "/assets/css/app.css"` — share the real bundle | Components render with the actual theme. Avoid creating a parallel `storybook.css`. |
| **Theme scoping** | `html.psb` resets to light; `.psb-variation-block .media-centarr` restores dark | Storybook chrome stays light/readable; component previews show our real theme. Don't touch this without reading [`references/sandboxing.md`](references/sandboxing.md). |
| **Dep env** | `{:phoenix_storybook, "~> 1.0", only: [:dev, :test]}` | `import PhoenixStorybook.Router` inside `if Mix.env() == :dev` is still validated at compile time. `:test` inclusion makes that compile pass. |
| **Backend module guard** | `if Mix.env() == :dev` wraps `defmodule MediaCentarrWeb.Storybook` | Without the guard, `:test` and `:prod` compile fails to find `PhoenixStorybook`. |
| **Tailwind source** | `assets/css/app.css` has `@source "../../storybook"` | Utilities used in stories must be scanned by Tailwind v4. New top-level dirs need the same treatment. |
| **Formatter** | `.formatter.exs` includes `"storybook/**/*.exs"` | Stories format alongside the rest of the code. |
| **Component coverage** | Every component module without a story must declare `@storybook_status :skip / :pending / :static_example` + `@storybook_reason "..."` | Enforced by `MediaCentarr.Credo.Checks.StorybookCoverage` (`mix precommit`). The reason lives next to the code so it can't drift. |

## Story types — choose the right one

| Type | Use | Required callback | Doc source |
|------|-----|-------------------|------------|
| `:component` | Stateless function components — most stories | `function/0` returning `&Module.fun/1` | `@doc` of the function |
| `:live_component` | Phoenix LiveComponents (rare in this repo) | `component/0` returning the module | `@moduledoc` |
| `:page` | Documentation, design-system overview, conventions reference | `render/1` (and optionally `navigation/0`, `doc/0`) | n/a |
| `:example` | Real-world UI showcase mixing multiple components | `mount/3` + `render/1` (LiveView lifecycle) | n/a |

For function components in `lib/media_centarr_web/components/**`, use `:component`. For the welcome/philosophy landing, use `:page`. Skip `:live_component` and `:example` until there's a proven need.

## Variation / VariationGroup — the API you'll use 90% of the time

Authoritative struct definitions (from `deps/phoenix_storybook/lib/phoenix_storybook/stories/variation.ex`):

```elixir
%Variation{
  id: atom,                              # required, unique within a story
  description: String.t() | nil,         # appears above the preview
  note: String.t() | nil,                # markdown, appears below the description
  attributes: map,                       # passed to the component as assigns
  slots: [String.t()],                   # HEEx fragments (one per inner_block)
  let: atom | nil,                       # for components using `:let={x}` on default slot
  template: :unset | String.t() | nil | false  # see "Templates" below
}

%VariationGroup{
  id: atom,                              # required
  description: String.t() | nil,
  note: String.t() | nil,
  variations: [Variation.t()],           # required
  template: :unset | String.t() | nil | false
}
```

`VariationGroup` renders all child variations side-by-side in **one preview block**. Use it for matrices (every variant, every size). Avoid using it as a generic "section" wrapper; if the variations don't share an axis, list them separately.

### Comprehensions are idiomatic

The seed `<.button>` story uses `for` inside `variations/0` to generate the matrix without boilerplate — the story length tracks interesting axes, not loops:

```elixir
%VariationGroup{
  id: :variants,
  description: "All variants at default (md) size",
  variations:
    for variant <- ~w(primary secondary action info risky danger dismiss neutral outline) do
      %Variation{
        id: String.to_atom(variant),
        attributes: %{variant: variant},
        slots: [label_for(variant)]
      }
    end
}
```

## Slots and `let`

Slots arrive as a list of HEEx string fragments — one entry per slot insertion (or per default-slot child).

**Default slot, plain content:**

```elixir
%Variation{
  id: :default,
  attributes: %{variant: "primary"},
  slots: ["Click me"]
}
```

**Named slots:**

```elixir
%Variation{
  id: :modal,
  slots: [
    """
    <:button><button type="button">Cancel</button></:button>
    """,
    """
    <:button><button type="button">OK</button></:button>
    """
  ]
}
```

**Default slot using `:let` (component declares `:let={x}` on `:inner_block`):**

```elixir
%Variation{
  id: :list,
  attributes: %{stories: ~w(apple banana cherry)},
  let: :entry,                           # name matches what the component yields
  slots: ["I like <%= entry %>"]
}
```

**Named slot with `:let`** (no `let:` key needed at the variation level — it's inline in the slot):

```elixir
%Variation{
  id: :table,
  attributes: %{rows: [%{first: "Jean"}, %{first: "Sam"}]},
  slots: [
    """
    <:col :let={user} label="First name"><%= user.first %></:col>
    """
  ]
}
```

## Templates — wrap the variation in custom markup

Define `template/0` to wrap **every** variation in a story. Use the magic `<.psb-variation/>` placeholder:

```elixir
def template do
  """
  <div class="my-wrapper">
    <.psb-variation/>
  </div>
  """
end
```

Override per-variation via `:template` in the variation struct. Set to `false` or `nil` to disable templating for that one.

For `VariationGroup`, choose **one of two** template strategies:

```elixir
# Wrap every variation individually
def template do
  ~s|<div class="card"><.psb-variation/></div>|
end

# Wrap the whole group in one container
def template do
  ~s|<div class="grid"><.psb-variation-group/></div>|
end
```

### Template tricks

- **Unique IDs:** the `:variation_id` placeholder substitutes the current variation's id at render time — useful when a wrapper needs a unique id per variation.
- **Pass extra attrs:** add attributes to the placeholder and they reach the variation: `<.psb-variation form={f}/>`. Useful when a parent component (`<.form>`) needs to wrap the preview.
- **Hide markup from the source preview:** add `psb-code-hidden` to a wrapping element to suppress it from the shown code while keeping it in the live preview:

```elixir
"""
<div psb-code-hidden>
  <button phx-click={Modal.show_modal()}>Open modal</button>
  <.psb-variation/>
</div>
"""
```

## Visibility for modal/slideover-style components

Two strategies depending on how the component manages its own visibility:

**JS-controlled** (CSS-toggling component, `Modal.show_modal()`-style):

```elixir
def template do
  """
  <div>
    <button phx-click={Modal.show_modal()}>Open modal</button>
    <.psb-variation/>
  </div>
  """
end
```

**Elixir-controlled** (`show={true}`-style assigns) — use `psb-assign`/`psb-toggle` events:

```elixir
def template do
  """
  <div>
    <button phx-click={JS.push("psb-assign", value: %{show: true})}>Open</button>
    <.psb-variation/>
  </div>
  """
end

%Variation{
  id: :default_slideover,
  attributes: %{
    close_event: JS.push("psb-assign", value: %{variation_id: :default_slideover, show: false})
  }
}
```

## Late evaluation — keep code-preview clean

When an attribute needs runtime evaluation but the displayed source should stay terse, wrap the value:

```elixir
%Variation{
  attributes: %{
    on_open: JS.push("open"),
    on_close: {:eval, ~s|JS.push("close")|}      # source shows: on_close={JS.push("close")}
  }
}
```

Without `{:eval, ...}` the preview would render the serialised `%Phoenix.LiveView.JS{}` struct.

## Source-code rendering

```elixir
def render_source, do: :function   # show only the function (best for function components)
def render_source, do: :module     # show the whole module (default for live_component)
def render_source, do: false       # disable the source tab entirely
```

For function components, **always set `:function`** — module source is noisy and irrelevant.

## Layout

```elixir
def layout, do: :two_columns       # default — preview left, source right
def layout, do: :one_column        # full-width preview, useful for tables/wide cards
```

## Container — when to escape into an iframe

Components share a single DOM with the storybook chrome. That's faster than iframes and what we want by default. **Escape into an iframe only when**:

- The component installs `document`-level listeners (rare).
- You're testing responsive CSS at narrow widths.

```elixir
def container, do: :iframe
def container, do: {:iframe, style: "display: inline; width: 320px;"}
def container, do: {:div, class: "my-extra-class"}    # default container with extras
```

Iframes trigger an extra HTTP fetch for `:live_component` stories. Don't reach for them reflexively.

## Aliases and imports — for nested components in slots

When a slot contains other components, declare aliases/imports so the slot HEEx stays terse:

```elixir
def aliases, do: [MediaCentarrWeb.JSHelpers]
def imports, do: [{MediaCentarrWeb.NestedComponent, nested: 1}]
```

Then slot content can call `<.nested phx-click={JSHelpers.toggle()}>...</.nested>` without fully-qualifying.

## Index files — sidebar customization

Each area has an `_<area>.index.exs` shaping its sidebar entry. Module name **must** be `MediaCentarrWeb.Storybook.<Area>` (Boundary).

```elixir
defmodule MediaCentarrWeb.Storybook.CoreComponents do
  use PhoenixStorybook.Index

  def folder_open?, do: true
  def folder_icon, do: {:fa, "rectangle-list", :light, "psb:mr-1"}
  def folder_index, do: 1                # numeric → appears earlier; omit → alphabetical

  def entry("button"), do: [icon: {:fa, "rectangle-ad", :thin}]
  def entry("flash"),  do: [icon: {:fa, "bolt", :thin}, name: "Flash messages"]
end
```

`entry/1` keys: `:icon`, `:name`, `:index`. Undefined entries use sensible defaults.

## Icons — every accepted form

```elixir
{:fa, "book"}                              # FontAwesome solid (free)
{:fa, "book", :thin}                       # FontAwesome thin (paid plan needed for some)
{:fa, "book", :solid, "psb:px-2"}          # extra css

{:hero, "cake"}                            # Heroicons outline (default)
{:hero, "cake", :solid, "psb:w-2 psb:h-2"} # Heroicons solid + sizing

{:local, "hero-cake"}                      # local span class — works with our heroicons CSS plugin
{:local, "my-icon", "psb:w-2 psb:h-2"}     # third arg is css (no style for :local)
```

Sizing/spacing classes inside icons must be `psb:`-prefixed because they live in storybook chrome, not the sandbox.

## Adding a new story (checklist)

1. Confirm the component **belongs** in storybook — re-read rule 8.
2. Create `storybook/<area>/<component>.story.exs`.
3. Module: `defmodule MediaCentarrWeb.Storybook.<Area>.<Component>`. **Always** `MediaCentarrWeb.Storybook.*`.
4. `use PhoenixStorybook.Story, :component` (or `:page` for docs).
5. `def function, do: &MediaCentarrWeb.<Area>.<component>/1`.
6. `def render_source, do: :function`.
7. `def variations do [...] end` — every meaningful state. Use `VariationGroup` + comprehensions for matrices.
8. Add an entry in `storybook/<area>/_<area>.index.exs`. Create the index module (`MediaCentarrWeb.Storybook.<Area>`) if the area is new.
9. If the component has nested components in slots, declare `aliases/0` / `imports/0`.
10. Run dev server, visit `/storybook/<area>/<component>`, verify previews render against the dark gradient.
11. `mix precommit` → push.

The seed example is `storybook/core_components/button.story.exs`. Copy its shape (variant matrix, size matrix, hero pair, destructive group, icon-only, disabled) when adding a multi-axis story.

## Coverage status (when not adding a story)

If you add a component but **don't** add a story (sticky state, orchestration-only, awaiting contract refactor), declare the status on the module immediately so the Credo check passes:

```elixir
defmodule MediaCentarrWeb.Components.Foo do
  @moduledoc "..."

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)

  @storybook_status :pending
  @storybook_reason "Awaiting typed-attr contract refactor — see plan"

  # ...
end
```

Statuses:

- `:skip` — never going to have a story (sticky LiveView state, orchestration-only, view-model struct, helpers). Always paired with a reason.
- `:static_example` — depends on context state in ways that prevent live rendering; a static visual specimen will be added.
- `:pending` — story is planned but not yet written. The check warns (does not fail precommit) until the story exists.

The `Module.register_attribute(..., persist: true)` calls are required to silence "unused module attribute" warnings under `--warnings-as-errors`. They also persist the attributes into the BEAM file so they're inspectable at runtime via `Module.get_attribute/2`.

Omit all four lines (the two `register_attribute` and the two `@` declarations) once a story is in place — the existence of the story file at `storybook/<area>/<func>.story.exs` is what marks the component as covered.

## Anti-patterns

| ❌ Don't | ✅ Do |
|---------|------|
| `defmodule Storybook.X` (auto-generator default) | `defmodule MediaCentarrWeb.Storybook.X` |
| Import factories from `test/support/` | Use obvious literal fixtures so a designer reading the story can reason about the output |
| Conditional rendering based on `data-input` mode | Cover the visual outcome statically; describe the mode in `:description` |
| Add logic-heavy assertions or snapshot diffs to a story | Cover behaviour in `automated-testing`; storybook is visuals only |
| Recreate `assets/css/storybook.css` / `storybook.js` | We deleted those on setup — point at our real `app.css`. Don't reintroduce them. |
| Reach for `def container, do: :iframe` to "fix" a styling issue | Almost always the issue is sandbox CSS, not isolation — see `references/sandboxing.md` |
| Use unprefixed Tailwind utilities in icon css | Icons live in chrome, not the sandbox — must be `psb:`-prefixed |
| Story attribute classes like `class="bg-emerald-400"` (the auto-generator template) | Don't override component styling in stories. The story shows the component's *real* output. |

## When the component is hard to story

If you reach for fake context state (mocked PubSub, fake LiveView assigns) to make a component renderable in storybook, **stop**. The component's contract is too coupled. Pick one:

- Push the contextual lookup up into the LiveView. The component becomes pure.
- Wrap the data shape in a typed struct/ViewModel the component accepts directly.
- Add the component to the **Skip** list in [`docs/storybook.md`](../../docs/storybook.md) with a note explaining why.

## Common errors and fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `module PhoenixStorybook.Router is not loaded` in `MIX_ENV=test` | Dep was `only: :dev` | Make it `only: [:dev, :test]`. The router import inside `if Mix.env() == :dev` is still validated at compile time. |
| `Storybook.X is not included in any boundary` | Module under `Storybook.*` namespace | Rename to `MediaCentarrWeb.Storybook.*`. |
| Storybook chrome shows light-on-light text | Daisy `:root { color-scheme: dark }` leaks into storybook chrome | The `html.psb` override in `assets/css/app.css` resets this. Don't remove it. |
| Component preview is light/unstyled | Theme override too aggressive — wiped variables for the whole storybook | The `html.psb .psb-variation-block .media-centarr` rule restores dark theme inside component previews specifically. Don't widen the selector to all `.media-centarr`; that re-darkens `:page` stories. |
| Stories missing from sidebar | New `<area>` directory has no `_<area>.index.exs` | Create the index. Fall back to the auto-generated default by omitting it, but you lose icon control. |
| Tailwind utility classes used in a story aren't generated | New top-level dir not in `@source` | Add `@source "../../<dir>"` to `assets/css/app.css`. |
| Compilation error: `module PhoenixStorybook is not loaded` in `lib/media_centarr_web/storybook.ex` | The backend module isn't gated by `if Mix.env() == :dev` | Wrap the whole `defmodule` in `if Mix.env() == :dev do … end`. |
| Iframe spinner forever on a `:live_component` story with `def container, do: :iframe` | Live components in iframes use a real HTTP fetch and need the route to be reachable | Verify `storybook_assets()` scope is mounted in the router. |

## See also

- [`docs/storybook.md`](../../docs/storybook.md) — philosophy, per-component triage, project routes
- [`user-interface`](../user-interface/SKILL.md) — component recipes; storybook stories are runnable companions
- [`automated-testing`](../automated-testing/SKILL.md) — where logic + assertions go
- [`references/sandboxing.md`](references/sandboxing.md) — deep dive on the chrome/sandbox split + theme override architecture
- [`references/api.md`](references/api.md) — full callback list, struct fields, configuration option reference
- [`references/recipes.md`](references/recipes.md) — copy-pasteable patterns for forms, tables, modals, slots-with-let, page stories
- [Phoenix Storybook hexdocs](https://hexdocs.pm/phoenix_storybook) — upstream
- Local guides: `deps/phoenix_storybook/guides/{components,sandboxing,theming,color_modes,icons,testing}.md` (already vendored)
