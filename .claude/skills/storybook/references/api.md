# Phoenix Storybook — full API reference

Authoritative source: `deps/phoenix_storybook/lib/phoenix_storybook/stories/{story,variation,index}.ex` and the guides in `deps/phoenix_storybook/guides/`. This document distills them into a single quick-reference for writing stories in this project. When in doubt, the upstream source wins.

## Story callbacks by type

### `:component` story

Required:

| Callback | Returns | Notes |
|----------|---------|-------|
| `function/0` | `&Module.fun/1` capture | Anonymous capture or local capture both work |

Optional:

| Callback | Returns | Default | Effect |
|----------|---------|---------|--------|
| `variations/0` | `[Variation.t() \| VariationGroup.t()]` | `[]` | The list of states displayed in Stories tab |
| `template/0` | HEEx string | `nil` | Wraps every variation; insert with `<.psb-variation/>` |
| `aliases/0` | `[atom]` | `[]` | Aliases available inside slot HEEx |
| `imports/0` | `[{module, [function: arity]}]` | `[]` | Imports available inside slot HEEx |
| `attributes/0` | List of `PhoenixStorybook.Attr.t()` | inferred from component | Override or supplement the component's `attr` declarations |
| `slots/0` | List of `PhoenixStorybook.Slot.t()` | inferred from component | Same idea for slots |
| `layout/0` | `:two_columns \| :one_column` | `:two_columns` | One-column = full-width preview |
| `render_source/0` | `:module \| :function \| false` | `:module` | Use `:function` for function components |
| `container/0` | `{:div, attrs} \| :iframe \| {:iframe, attrs}` | `{:div, []}` | Switch to iframe only when truly needed |

### `:live_component` story

Required:

| Callback | Returns | Notes |
|----------|---------|-------|
| `component/0` | the LiveComponent module | E.g. `MediaCentarrWeb.SomeLiveComp` |

Optional: same set as `:component` plus:

| Callback | Returns | Effect |
|----------|---------|--------|
| `handle_info/2` | LiveView-style return | Process messages dispatched to the embedded live component |

### `:page` story

Optional:

| Callback | Returns | Default | Effect |
|----------|---------|---------|--------|
| `doc/0` | String | `nil` | Subtitle below the page title |
| `navigation/0` | `[{atom, String.t(), icon_tuple}]` | `[]` | Tabs at the top right; current tab arrives in render assigns as `:tab` |
| `render/1` | HEEx | required to render anything | Receives `assigns` (with `:tab` if `navigation/0` is set) |

The welcome page in `storybook/welcome.story.exs` is the local reference example.

### `:example` story

For real-world UI showcases that mix multiple components. Behaves like a child LiveView.

Optional:

| Callback | Returns | Notes |
|----------|---------|-------|
| `doc/0` | String | Description text |
| `extra_sources/0` | `[String.t()]` | Relative file paths shown alongside the story source |
| `mount/3` | LiveView mount return | Standard LiveView lifecycle |
| `render/1` | HEEx | Standard LiveView render |
| `handle_event/3` | LiveView event return | Standard LiveView lifecycle |

**Caveat:** `handle_params/3` is **not supported** in example stories.

## Variation struct

```elixir
%PhoenixStorybook.Stories.Variation{
  id: atom,                              # @enforce_keys — required
  description: String.t() | nil,         # default: nil
  note: String.t() | nil,                # markdown — default: nil
  let: atom | nil,                       # default: nil
  slots: [String.t()],                   # default: []
  attributes: map,                       # default: %{}
  template: :unset | String.t() | nil | false   # default: :unset
}
```

`template: :unset` means "use the story's `template/0`". `nil` or `false` means "do not template this variation".

`note` is rendered as Markdown below the description. Use it for caveats ("requires `feature_x` enabled", "deprecated — use Y") rather than core docs.

`attributes` types are validated against the component's `attr` declarations at compile time and will raise a compile error on mismatch.

## VariationGroup struct

```elixir
%PhoenixStorybook.Stories.VariationGroup{
  id: atom,                              # @enforce_keys — required
  description: String.t() | nil,
  note: String.t() | nil,
  variations: [Variation.t()],           # @enforce_keys — required
  template: :unset | String.t() | nil | false
}
```

Variations inside a group share one preview block. Their individual `note` values are **ignored** — only the group's `note` is shown.

Two valid template strategies for groups:

```elixir
# Each variation wrapped individually
def template do
  ~s|<div class="card"><.psb-variation/></div>|
end

# Whole group wrapped once
def template do
  ~s|<div class="grid"><.psb-variation-group/></div>|
end
```

## Template DSL

Inside `template/0` (and per-variation overrides):

| Placeholder / attribute | Effect |
|-------------------------|--------|
| `<.psb-variation/>` | Where the variation HEEx is injected |
| `<.psb-variation-group/>` | Same, for whole-group templates |
| `:variation_id` (anywhere in the template string) | Substituted with the variation's id at render time — useful for unique ids |
| `<.psb-variation form={f}/>` | Extra attributes are forwarded to the variation's component invocation |
| `psb-code-hidden` (HTML attribute on a wrapping element) | Hide that element + descendants from the source preview while keeping it live in the rendered output |

## Magic events

For Elixir-side state on modal/slideover-style components:

```elixir
JS.push("psb-assign", value: %{show: true})
JS.push("psb-toggle", value: %{key: :show})

# Per-variation targeting:
JS.push("psb-assign", value: %{variation_id: :default, show: false})
```

Storybook intercepts these events and merges `value` into the variation's assigns map. Without `:variation_id`, the assignment applies to every variation in the story.

## Late evaluation

Wrap an attribute value in `{:eval, "literal expression"}` to evaluate it at runtime but render the literal expression as the source preview. Use case: JS commands and other complex values that would otherwise serialise into noisy struct prints.

```elixir
%Variation{
  attributes: %{
    on_close: {:eval, ~s|JS.push("close")|}
  }
}
# Source preview:  on_close={JS.push("close")}
# Runtime value:   %Phoenix.LiveView.JS{ops: [["push", %{event: "close"}]]}
```

## Slots cheat sheet

```elixir
# Default slot, plain content
slots: ["Click me"]

# Default slot with `:let` (component declares :let={x} on inner_block)
attributes: %{stories: ~w(a b c)},
let: :entry,
slots: ["I like <%= entry %>"]

# Named slots (no let key needed at variation level)
slots: [
  ~s|<:button>Cancel</:button>|,
  ~s|<:button>OK</:button>|
]

# Named slot with :let inline
slots: [
  """
  <:col :let={user} label="First name"><%= user.first %></:col>
  """
]
```

## Index module callbacks

```elixir
defmodule MediaCentarrWeb.Storybook.<Area> do
  use PhoenixStorybook.Index
end
```

| Callback | Returns | Default | Effect |
|----------|---------|---------|--------|
| `folder_name/0` | String | derived from filename | Sidebar label |
| `folder_icon/0` | icon tuple | none | Icon left of the folder name |
| `folder_open?/0` | boolean | `false` | Initial expanded state |
| `folder_index/0` | integer | none | Sort position; lower = earlier; absent = alphabetical |
| `entry/1` | keyword list | empty | Per-story override; key = story filename without extension |

`entry/1` keys: `:icon`, `:name`, `:index`. Sorting: numeric indexes first (ascending), then alphabetical by filename.

## Icon tuple forms (every supported shape)

```elixir
{:fa, "book"}                              # FA solid
{:fa, "book", :thin}                       # FA thin
{:fa, "book", :solid, "psb:px-2"}          # FA solid + extra css
{:hero, "cake"}                            # Heroicons outline
{:hero, "cake", :solid}
{:hero, "cake", :outline, "psb:w-2 psb:h-2"}
{:local, "hero-cake"}                      # local span class
{:local, "hero-cake", "psb:w-2 psb:h-2"}   # 3rd arg is css; no style support for :local
```

CSS classes inside icons must be `psb:`-prefixed (icons live in chrome).

## `use PhoenixStorybook` configuration options

Authoritative: `lib/media_centarr_web/storybook.ex` plus the upstream `PhoenixStorybook` moduledoc. Frequently used:

| Option | Type | Default | Purpose |
|--------|------|---------|---------|
| `otp_app` | atom | required | OTP app for static asset resolution |
| `content_path` | string | required | Absolute path to the storybook stories directory |
| `css_path` | string | none | Remote URL to the component stylesheet (loaded in the `app` CSS layer) |
| `js_path` | string | none | Remote URL to a JS bundle that sets `window.storybook = { Hooks, Params, Uploaders }` |
| `js_script_type` | string | none | Set to `"module"` if `js_path` uses ES module imports |
| `sandbox_class` | string | `"my-app-sandbox"` | Class added to all sandbox containers — also apply to your live app body for parity |
| `title` | string | `"Live Storybook"` | Chrome title |
| `themes` | list | `[]` | Named themes shown in the chrome's theme dropdown |
| `themes_strategies` | keyword | `[sandbox_class: "theme"]` | How active theme propagates: `:sandbox_class`, `:assign`, `:function` |
| `color_mode` | boolean | `false` | Enables the chrome's light/dark/system picker |
| `color_mode_sandbox_dark_class` | string | `"dark"` | Class set on sandbox in dark mode |
| `color_mode_sandbox_light_class` | string | none | Class set on sandbox in light mode (only if you need an explicit light class) |
| `font_awesome_plan` | `:free \| :pro` | `:free` | FontAwesome subscription tier |
| `font_awesome_kit_id` | string | none | FA kit id (Web Fonts + CSS Only when configuring) |
| `font_awesome_css_path` | string | none | Skip FA bundle, use your existing CSS |
| `font_awesome_rendering` | `:svg \| :webfont` | `:svg` | Render mode |
| `strip_doc_attributes` | boolean | `true` | Whether to hide private/private-looking attrs in doc |
| `compilation_mode` | `:lazy \| :eager` | `:lazy` (dev), `:eager` (prod) | Story loading strategy |
| `compilation_debug` | boolean | `false` | Logs story compilation steps |

In this repo we use only `otp_app`, `content_path`, `css_path`, and `sandbox_class`. Adding more is fine, but coordinate with the dark-theme override in `assets/css/app.css`.

## Router macros

From `import PhoenixStorybook.Router` (must be inside the same `if Mix.env() == :dev` block as the macro calls — see project conventions in SKILL.md):

| Macro | Effect |
|-------|--------|
| `storybook_assets()` | Mounts the assets controller routes (CSS, JS, FA, etc.) |
| `live_storybook("/storybook", backend_module: MediaCentarrWeb.Storybook)` | Mounts the storybook LiveSession at the given path |

Routes generated (see `mix phx.routes` filtered by storybook in `:dev`):

```
GET   /storybook                     PhoenixStorybook.StoryLive :root
GET   /storybook/*story              PhoenixStorybook.StoryLive :story
GET   /storybook/iframe/*story       PhoenixStorybook.Story.ComponentIframeLive :story_iframe
GET   /storybook/visual_tests        PhoenixStorybook.VisualTestLive :range
GET   /storybook/visual_tests/*story PhoenixStorybook.VisualTestLive :show
GET   /storybook/assets/...          PhoenixStorybook.AssetsController
```

The `visual_tests` endpoints render component stories without the chrome — useful for screenshot/diff tooling. They are dev-only along with the rest of the routes.
