defmodule MediaCentarrWeb.Storybook.Detail.FacetStrip do
  @moduledoc """
  Single-row label-on-top column strip used inside the entity detail panel.

  Each variation is a list of typed `Detail.Facet` structs constructed via
  the `Facet.text/2`, `Facet.chips/2`, and `Facet.rating/3` helpers — the
  helpers encode each kind's expected value shape, so the storybook never
  hand-builds `%Facet{kind: ...}` literals. This is the cleanest example
  of the storybook initiative's typed-attr / view-model contract.

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
      }
    ]
  end
end
