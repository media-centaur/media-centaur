defmodule MediaCentarrWeb.Storybook.LibraryCards.Toolbar do
  @moduledoc """
  Library page toolbar — tabs (All / Movies / TV) with count badges,
  custom sort dropdown, and a debounced filter input.

  ## Contract shape

  The toolbar's contract is already typed:

      attr :active_tab, :atom, required: true       # :all | :movies | :tv
      attr :counts, :map, required: true            # %{all: int, movies: int, tv: int}
      attr :sort_order, :atom, required: true       # :recent | :alpha | :year
      attr :sort_open, :boolean, required: true
      attr :sort_highlight, :integer, required: true
      attr :filter_text, :string, required: true

  Only `:counts` is `:map`, but the shape is small and well-known so the
  fixtures construct it directly. No view-model refactor needed.

  ## Variation matrix

    * Tab axis — `:active_tab` toggled across the three tabs (badge counts
      stay constant).
    * Sort dropdown states — closed (showing each `sort_order` label) and
      open (sweeping `sort_highlight` across the three items).
    * Filter input — empty placeholder vs active filter text.
    * Edge cases — zero counts and very large counts (badge layout
      stress test).

  ## Visual note

  The open dropdown uses `position: absolute` and overlays the next
  variation. The template gives every variation 14rem of bottom padding
  so the open menu has room to render without colliding with the next
  preview block.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.Components.LibraryCards.toolbar/1
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
        description:
          "Tab axis — `active_tab` highlights one of `All` / `Movies` / `TV`. " <>
            "Badge counts stay constant across the three variations.",
        variations:
          for {tab, suffix} <- [{:all, "all"}, {:movies, "movies"}, {:tv, "tv"}] do
            %Variation{
              id: String.to_atom(suffix <> "_active"),
              attributes:
                base_attrs(
                  active_tab: tab,
                  counts: %{all: 42, movies: 18, tv: 24}
                )
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
          "Filter input — empty (placeholder visible) and populated with " <>
            "a generic search term.",
        variations: [
          %Variation{
            id: :empty_filter,
            description: "No filter — placeholder text visible.",
            attributes: base_attrs(filter_text: "")
          },
          %Variation{
            id: :active_filter,
            description: "Filter populated with a generic term.",
            attributes: base_attrs(filter_text: "drama")
          }
        ]
      },
      %VariationGroup{
        id: :edge_cases,
        description: "Count-badge edge cases — zero and four-digit values.",
        variations: [
          %Variation{
            id: :zero_counts,
            description: "All counts zero — badges still render the literal `0`.",
            attributes: base_attrs(counts: %{all: 0, movies: 0, tv: 0})
          },
          %Variation{
            id: :large_counts,
            description:
              "Four-digit counts — badge layout must not wrap or push the " <>
                "filter input off the row.",
            attributes: base_attrs(counts: %{all: 9999, movies: 4321, tv: 1234})
          }
        ]
      }
    ]
  end

  # --- Fixtures ----------------------------------------------------------

  # Default attribute set; pass keyword overrides for the axis under test.
  defp base_attrs(overrides \\ []) do
    defaults = [
      active_tab: :all,
      counts: %{all: 42, movies: 18, tv: 24},
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
