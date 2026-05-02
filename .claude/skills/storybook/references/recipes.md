# Storybook recipes

Copy-pasteable patterns for the situations you'll hit. Adjust modules and attribute names to match the component you're storying.

## Recipe 1 — Multi-axis component (variant × size × shape)

The seed: `storybook/core_components/button.story.exs`. Use `VariationGroup` per axis, comprehensions for ids:

```elixir
defmodule MediaCentarrWeb.Storybook.CoreComponents.Button do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.CoreComponents.button/1
  def render_source, do: :function

  def variations do
    [
      %VariationGroup{
        id: :variants,
        description: "All variants at default size",
        variations:
          for variant <- ~w(primary secondary action info risky danger dismiss neutral outline) do
            %Variation{
              id: String.to_atom(variant),
              attributes: %{variant: variant},
              slots: [label_for(variant)]
            }
          end
      },
      %VariationGroup{
        id: :sizes,
        description: "Size axis on the primary variant",
        variations:
          for size <- ~w(xs sm md lg) do
            %Variation{
              id: String.to_atom("primary_" <> size),
              attributes: %{variant: "primary", size: size},
              slots: ["Play"]
            }
          end
      }
    ]
  end

  defp label_for("primary"), do: "Play"
  defp label_for(_), do: "Action"
end
```

## Recipe 2 — Card with typed-attr struct

For a component whose contract is a struct (`<.poster_card entity={...}>`), build the struct in a private helper. Designers reading the story should be able to look at the literal and map it to what they see on screen:

```elixir
defmodule MediaCentarrWeb.Storybook.LibraryCards.PosterCard do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.LibraryCards.poster_card/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :loaded,
        description: "Has artwork, full metadata",
        attributes: %{entity: sample_entity()}
      },
      %Variation{
        id: :no_artwork,
        description: "Missing poster — placeholder visible",
        attributes: %{entity: %{sample_entity() | poster_url: nil}}
      },
      %Variation{
        id: :in_progress,
        description: "Watch progress 47%",
        attributes: %{entity: %{sample_entity() | progress_pct: 47}}
      },
      %Variation{
        id: :long_title,
        description: "Title overflow — verifies truncate behaviour",
        attributes: %{entity: %{sample_entity() | title: String.duplicate("Long ", 20)}}
      }
    ]
  end

  defp sample_entity do
    %{
      id: 1,
      title: "Sample Show",
      year: 2023,
      poster_url: "/images/storybook/sample-poster.jpg",
      progress_pct: nil
    }
  end
end
```

Don't import factories from `test/support`. The point of an obvious literal is that a designer can reason about the rendered output without reading factory code.

## Recipe 3 — Component with named slots

```elixir
defmodule MediaCentarrWeb.Storybook.Components.DetailPanel do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.DetailPanel.detail_panel/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :movie,
        attributes: %{title: "Sample Movie", year: 2023},
        slots: [
          ~s|<:hero><img src="/images/storybook/backdrop.jpg" alt="" /></:hero>|,
          """
          <:metadata>
            <span class="badge">2023</span>
            <span class="badge">2h 14m</span>
          </:metadata>
          """,
          ~s|Plot summary goes here.|
        ]
      }
    ]
  end
end
```

## Recipe 4 — Modal / slideover with template-controlled visibility

JS-controlled (component toggles itself):

```elixir
defmodule MediaCentarrWeb.Storybook.Components.Modal do
  use PhoenixStorybook.Story, :component

  alias MediaCentarrWeb.Modal

  def function, do: &Modal.modal/1
  def render_source, do: :function

  def template do
    """
    <div>
      <button class="btn" phx-click={Modal.show_modal()}>Open modal</button>
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{id: "default-modal"},
        slots: [~s|<:body>Hello world</:body>|]
      }
    ]
  end
end
```

Elixir-controlled (component reads `show={true|false}` from assigns):

```elixir
def template do
  """
  <div>
    <button phx-click={JS.push("psb-assign", value: %{show: true})}>Open</button>
    <.psb-variation/>
  </div>
  """
end

def variations do
  [
    %Variation{
      id: :default,
      attributes: %{
        show: false,
        on_close: JS.push("psb-assign", value: %{variation_id: :default, show: false})
      }
    }
  ]
end
```

## Recipe 5 — Form-wrapped component

When a component is meant to live inside a `<.form>`, use the template to provide the form:

```elixir
def template do
  """
  <.form for={%{}} as={:user} :let={f}>
    <.psb-variation form={f}/>
  </.form>
  """
end

def variations do
  [
    %Variation{
      id: :email,
      attributes: %{type: "email", label: "Email", name: "user[email]"}
    }
  ]
end
```

The `form={f}` attribute on `<.psb-variation/>` is forwarded to the component invocation.

## Recipe 6 — Table with `:let` per column

```elixir
%Variation{
  id: :people,
  attributes: %{
    rows: [
      %{first: "Ada", last: "Lovelace"},
      %{first: "Alan", last: "Turing"}
    ]
  },
  slots: [
    ~s|<:col :let={p} label="First"><%= p.first %></:col>|,
    ~s|<:col :let={p} label="Last"><%= p.last %></:col>|
  ]
}
```

## Recipe 7 — Page story (docs / philosophy / index)

```elixir
defmodule MediaCentarrWeb.Storybook.<Area>.<PageName> do
  use PhoenixStorybook.Story, :page

  def doc, do: "Short subtitle"

  def navigation do
    [
      {:overview, "Overview", {:fa, "circle-info", :thin}},
      {:examples, "Examples", {:fa, "code", :thin}}
    ]
  end

  def render(assigns = %{tab: :overview}) do
    ~H"""
    <div class="psb:prose psb:max-w-none psb:p-6">
      <h2>Overview</h2>
      <p>...</p>
    </div>
    """
  end

  def render(assigns = %{tab: :examples}) do
    ~H"""
    <div class="psb:prose psb:max-w-none psb:p-6">
      <h2>Examples</h2>
      ...
    </div>
    """
  end
end
```

Pages render in storybook chrome (light), so use `psb:`-prefixed Tailwind utilities for layout/typography. Don't apply our `glass-surface` or theme-specific colors here — those belong in component previews.

## Recipe 8 — Override displayed source code

For function components, almost always want only the function, not the whole module:

```elixir
def render_source, do: :function
```

To hide source entirely (rare, e.g. when the component is purely visual and source is noise):

```elixir
def render_source, do: false
```

## Recipe 9 — Wide / full-width preview

Tables, dense rows, anything that needs the full canvas:

```elixir
def layout, do: :one_column
```

## Recipe 10 — Nested component imports/aliases

Slot HEEx referencing other modules — declare imports/aliases so the slot stays terse:

```elixir
def aliases, do: [MediaCentarrWeb.JSHelpers]
def imports, do: [{MediaCentarrWeb.NestedComponent, nested: 1}]

def variations do
  [
    %Variation{
      id: :default,
      slots: [
        """
        <.nested phx-click={JSHelpers.toggle()}>hello</.nested>
        """
      ]
    }
  ]
end
```

## Recipe 11 — Adding a new index module

When you create a new story area, the auto-generated sidebar entry is alphabetical and unicon'd. Customise:

```elixir
# storybook/library_cards/_library_cards.index.exs
defmodule MediaCentarrWeb.Storybook.LibraryCards do
  use PhoenixStorybook.Index

  def folder_name, do: "Library cards"
  def folder_icon, do: {:fa, "rectangle-list", :light, "psb:mr-1"}
  def folder_open?, do: true
  def folder_index, do: 2     # appears after :core_components (index 1)

  def entry("poster_card"), do: [icon: {:fa, "image-portrait", :thin}]
  def entry("cw_card"),     do: [icon: {:fa, "play", :thin}, name: "Continue Watching"]
  def entry("toolbar"),     do: [icon: {:fa, "bars-staggered", :thin}]
end
```

Note the module name **must** be `MediaCentarrWeb.Storybook.<Area>` for Boundary classification.

## Recipe 12 — Static example for a stateful component

Some components depend on real state (focus context, PubSub feeds). Don't synthesize fake state — capture a single representative visual:

```elixir
def variations do
  [
    %Variation{
      id: :default,
      description: "Static visual — runtime behaviour requires the input system; see [`docs/input-system.md`](../../docs/input-system.md).",
      attributes: %{items: sample_items()}
    }
  ]
end

defp sample_items do
  [
    %{title: "Sample A"},
    %{title: "Sample B"},
    %{title: "Sample C"}
  ]
end
```

If the component can't be made meaningful without faking state, move it to the **Skip** list in `docs/storybook.md` instead of writing a misleading story.
