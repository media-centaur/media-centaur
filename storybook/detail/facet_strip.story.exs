defmodule MediaCentarrWeb.Storybook.Detail.FacetStrip do
  @moduledoc """
  Single-row label-on-top column strip used inside the entity detail panel.

  Each variation is a list of typed `Detail.Facet` structs constructed via
  the `Facet.text/2`, `Facet.chips/2`, and `Facet.rating/3` helpers — the
  helpers encode each kind's expected value shape, so the storybook never
  hand-builds `%Facet{kind: ...}` literals. This is the cleanest example
  of the storybook initiative's typed-attr / view-model contract.

  Two layouts are catalogued:

    * `:row` (default) — auto-fit horizontal grid with vertical dividers.
       The detail panel uses this below the `xl:` breakpoint, where the
       strip spans the full panel width.

    * `:stacked` — 2-column compact grid. The detail panel switches to
       this at `xl:+`, where the strip lives in a narrow right-hand
       sidebar beside the synopsis.

  An empty `facets` list is a valid input and renders nothing — the
  `:empty` variation pins that contract.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentarrWeb.Components.Detail.Facet

  def function, do: &MediaCentarrWeb.Components.Detail.FacetStrip.facet_strip/1
  def aliases, do: [Facet]
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="w-full max-w-3xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :text_only,
        description:
          "Three text-kind facets (Year, Genre, Runtime) — the densest text-only strip the detail panel renders.",
        attributes: %{
          facets: [
            Facet.text("Year", "2024"),
            Facet.text("Genre", "Drama"),
            Facet.text("Runtime", "2h 8m")
          ]
        }
      },
      %Variation{
        id: :chips,
        description:
          "Two chips-kind facets — list values are joined with the middle-dot separator " <>
            "and wrap inline within their column.",
        attributes: %{
          facets: [
            Facet.chips("Cast", ["Actor One", "Actor Two", "Actor Three"]),
            Facet.chips("Tags", ["Placeholder", "Sample", "Demo"])
          ]
        }
      },
      %Variation{
        id: :rating,
        description:
          "Single rating-kind facet — coloured numeric value with star glyph and a vote-count subtext " <>
            "(formatted as `1.2k` once counts cross the thousand boundary).",
        attributes: %{
          facets: [
            Facet.rating("Rating", 7.8, 1234)
          ]
        }
      },
      %Variation{
        id: :mixed_kinds,
        description:
          "Realistic detail-panel strip — text, chips, and rating side-by-side. " <>
            "The grid uses `auto-fit, minmax(140px, 1fr)` so columns share the row evenly.",
        attributes: %{
          facets: [
            Facet.text("Year", "2024"),
            Facet.chips("Genres", ["Drama", "Adventure"]),
            Facet.rating("Rating", 8.2, 4567)
          ]
        }
      },
      %Variation{
        id: :single_facet,
        description:
          "One facet only — the column has no left border (the `first:border-l-0` rule), " <>
            "so a lone facet sits flush with the strip's left edge.",
        attributes: %{
          facets: [
            Facet.text("Year", "2024")
          ]
        }
      },
      %Variation{
        id: :empty,
        description:
          "Empty `facets` list — graceful degradation: the component renders nothing " <>
            "(no border, no grid), so calling templates don't need to guard.",
        attributes: %{facets: []}
      },
      %VariationGroup{
        id: :stacked,
        description:
          "`:stacked` layout — compact 2-column mini-grid for narrow sidebar contexts. " <>
            "The detail panel uses this at `xl:+` where the strip lives beside the synopsis " <>
            "instead of below it. 4 facets become a 2×2; 3 facets become a 2+1 with one " <>
            "empty cell; a single facet sits alone.",
        template: ~s|<div class="w-[540px]"><.psb-variation/></div>|,
        variations: [
          %Variation{
            id: :stacked_four_facets,
            description:
              "TV-series shape (Network, Original Language, Genres, Rating) — fills the " <>
                "2×2 grid exactly. Roughly the height of a 4-line synopsis at `text-sm`, " <>
                "which is what the detail-panel reflow is tuned to balance.",
            attributes: %{
              layout: :stacked,
              facets: [
                Facet.text("Network", "Sample Network"),
                Facet.text("Original Language", "en"),
                Facet.chips("Genres", ["Drama", "Comedy"]),
                Facet.rating("Rating", 8.3, 1342)
              ]
            }
          },
          %Variation{
            id: :stacked_three_facets,
            description:
              "Movie shape (Director, Genres, Rating) — 2+1 layout with one empty cell on " <>
                "the second row. The empty cell is intentional: keeping a stable column " <>
                "axis makes the sidebar feel consistent across entity types.",
            attributes: %{
              layout: :stacked,
              facets: [
                Facet.text("Director", "Director Name"),
                Facet.chips("Genres", ["Drama", "Comedy"]),
                Facet.rating("Rating", 7.4, 142)
              ]
            }
          },
          %Variation{
            id: :stacked_single_facet,
            description:
              "Single-facet edge case — sits alone in the first cell, second cell of the row " <>
                "is empty. No left-border specialisation here (unlike `:row`'s `first:border-l-0`) " <>
                "because `:stacked` separates rows with grid gaps, not vertical rules.",
            attributes: %{
              layout: :stacked,
              facets: [
                Facet.text("Year", "2024")
              ]
            }
          }
        ]
      }
    ]
  end
end
