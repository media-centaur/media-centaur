defmodule MediaCentaurWeb.Storybook.LibraryCards.Toolbar do
  @moduledoc """
  Library page toolbar — tabs (All / Movies / TV), a custom sort
  dropdown, and a debounced filter input. Per-type counts live in the
  page heading (`50 titles · 33 movies · 17 shows`), not on the tabs.

  ## Contract shape

  The toolbar's contract is fully typed with scalar attrs:

      attr :active_tab, :atom, required: true       # :all | :movies | :tv
      attr :sort_order, :atom, required: true       # :recent | :alpha | :year
      attr :sort_open, :boolean, required: true
      attr :sort_highlight, :integer, required: true
      attr :filter_text, :string, required: true

  ## Variation matrix

    * Tab axis — `:active_tab` toggled across the three tabs.
    * Sort dropdown states — closed (showing each `sort_order` label) and
      open (sweeping `sort_highlight` across the three items).
    * Filter input — collapsed (idle/empty) vs expanded (holding a term).

  ## Visual note

  The open dropdown uses `position: absolute` and overlays the next
  variation. The template gives every variation 14rem of bottom padding
  so the open menu has room to render without colliding with the next
  preview block.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.LibraryCards.toolbar/1
  def render_source, do: :function

  # The open sort menu drops below the trigger via `position: absolute`,
  # so without padding it lands inside the next preview block. 14rem
  # comfortably clears the three-item menu.
  def template do
    """
    <div class="pb-56">
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
        description:
          "Sort dropdown closed — the trigger label tracks `sort_order` " <>
            "via `sort_label/1`. `sort_highlight` is irrelevant when closed.",
        variations:
          for {order, suffix} <- [{:recent, "recent"}, {:alpha, "alpha"}, {:year, "year"}] do
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
      %VariationGroup{
        id: :sort_open,
        description:
          "Sort dropdown open — `sort_order: :recent` makes the first item " <>
            "the *active* (primary-coloured) one. `sort_highlight` then sweeps " <>
            "across indices 0/1/2 to show how keyboard highlight stacks on top " <>
            "of the active item (index 0) vs sits alone on a non-active item.",
        variations:
          for highlight <- 0..2 do
            %Variation{
              id: String.to_atom("open_highlight_" <> Integer.to_string(highlight)),
              attributes:
                base_attrs(
                  sort_order: :recent,
                  sort_open: true,
                  sort_highlight: highlight
                )
            }
          end
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
            description: "Filter populated with a generic term — expanded to full width.",
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
      sort_highlight: 0,
      filter_text: ""
    ]

    defaults
    |> Keyword.merge(overrides)
    |> Map.new()
  end
end
