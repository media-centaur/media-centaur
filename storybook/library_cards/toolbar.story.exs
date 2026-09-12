defmodule MediaCentaurWeb.Storybook.LibraryCards.Toolbar do
  @moduledoc """
  Library page toolbar — tabs (All / Movies / TV), the sort control (a
  `GlassMenu.menu_select`), and a debounced filter input. Per-type counts
  live in the page heading (`50 titles · 33 movies · 17 shows`), not on
  the tabs.

  ## Contract shape

  The toolbar's contract is fully typed with scalar attrs:

      attr :active_tab, :atom, required: true       # :all | :movies | :tv
      attr :sort_order, :atom, required: true       # :recent | :watched | :alpha | :year
      attr :sort_open, :boolean, required: true
      attr :filter_text, :string, required: true

  ## Variation matrix

    * Tab axis — `:active_tab` toggled across the three tabs.
    * Sort dropdown states — closed (showing each `sort_order` label) and open.
    * Filter input — collapsed (idle/empty) vs expanded (holding a term).

  ## Visual note

  The open dropdown uses `position: absolute` and overlays the next
  variation. The template gives every variation 16rem of bottom padding
  so the open menu has room to render without colliding with the next
  preview block.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.LibraryCards.toolbar/1
  def render_source, do: :function

  # The open sort menu drops below the trigger via `position: absolute`,
  # so without padding it lands inside the next preview block. 16rem
  # comfortably clears the four-item menu.
  def template do
    """
    <div class="pb-64">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %VariationGroup{
        id: :tab_axis,
        description: "Tab axis — `active_tab` highlights one of `All` / `Movies` / `TV`.",
        variations:
          for {tab, suffix} <- [{:all, "all"}, {:movies, "movies"}, {:tv, "tv"}] do
            %Variation{
              id: String.to_atom(suffix <> "_active"),
              attributes: base_attrs(active_tab: tab)
            }
          end
      },
      %VariationGroup{
        id: :sort_closed,
        description: "Sort dropdown closed — the trigger label tracks `sort_order` via `sort_label/1`.",
        variations:
          for {order, suffix} <- [
                {:recent, "recent"},
                {:watched, "watched"},
                {:alpha, "alpha"},
                {:year, "year"}
              ] do
            %Variation{
              id: String.to_atom("closed_" <> suffix),
              attributes:
                base_attrs(
                  sort_order: order,
                  sort_open: false
                )
            }
          end
      },
      %Variation{
        id: :sort_open,
        description: "Sort dropdown open — the current order (`:recent`) is the active item.",
        attributes: base_attrs(sort_order: :recent, sort_open: true)
      },
      %VariationGroup{
        id: :filter_states,
        description:
          "Filter input collapses to an icon while idle (empty + unfocused) and " <>
            "grows to full width once it holds a term. The two states below show " <>
            "the collapse/expand endpoints; the focus transition is CSS-only.",
        variations: [
          %Variation{
            id: :empty_filter,
            description: "No filter — collapsed to an icon-only pill (unfocused).",
            attributes: base_attrs(filter_text: "")
          },
          %Variation{
            id: :active_filter,
            description:
              "Filter populated with a generic term — expanded to full width, " <>
                "with the inline clear (×) button that appears once the field holds text.",
            attributes: base_attrs(filter_text: "drama")
          }
        ]
      }
    ]
  end

  # --- Fixtures ----------------------------------------------------------

  # Default attribute set; pass keyword overrides for the axis under test.
  defp base_attrs(overrides) do
    defaults = [
      active_tab: :all,
      sort_order: :recent,
      sort_open: false,
      filter_text: ""
    ]

    defaults
    |> Keyword.merge(overrides)
    |> Map.new()
  end
end
