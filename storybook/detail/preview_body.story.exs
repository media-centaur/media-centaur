defmodule MediaCentaurWeb.Storybook.Detail.PreviewBody do
  @moduledoc """
  The facts of a not-yet-owned title under the cinematic frame's lockup:
  metadata row with the media-type badge, overview, facet strip, top
  cast. One body for the plan modal's movie confirm stage and the
  Discovery title detail modal.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Library.Person
  alias MediaCentaurWeb.Components.Detail.Facet
  alias MediaCentaurWeb.Components.Detail.TitlePreview

  def function, do: &MediaCentaurWeb.Components.Detail.PreviewBody.preview_body/1
  def render_source, do: :function
  def layout, do: :one_column

  defp movie do
    %TitlePreview{
      media_type: :movie,
      tmdb_id: "777",
      title: "Sample Movie",
      overview: "A drifter arrives in a coastal town the day the lighthouse goes dark.",
      metadata_items: ["2010", "2h 19m", "R", "US"],
      facets: [
        Facet.text("Director", "Jane Director"),
        Facet.rating("Rating", 8.2, 26_000),
        Facet.text("Original language", "en"),
        Facet.chips("Genres", ["Drama", "Mystery"])
      ],
      cast: [
        %Person{name: "Actor One", character: "The Drifter", order: 0},
        %Person{name: "Actor Two", character: "Lighthouse Keeper", order: 1}
      ],
      in_library?: false
    }
  end

  def variations do
    [
      %Variation{
        id: :movie,
        description: "A movie: metadata row, overview, facets, top cast.",
        attributes: %{preview: movie()}
      },
      %Variation{
        id: :series,
        description: "A series: the TV badge, season count in the row, Network in the strip.",
        attributes: %{
          preview: %{
            movie()
            | media_type: :tv_series,
              title: "Sample Show",
              metadata_items: ["2008", "5 seasons", "US"],
              facets: [Facet.text("Network", "Sample Network"), Facet.chips("Genres", ["Drama"])]
          }
        }
      },
      %Variation{
        id: :with_library_state,
        description: "The plan modal's variant adds the in-your-library line beside the row.",
        attributes: %{preview: %{movie() | in_library?: true}, library_state: true}
      },
      %Variation{
        id: :sparse,
        description: "TMDB knows only the title: the row alone, nothing else earns pixels.",
        attributes: %{
          preview: %TitlePreview{
            media_type: :movie,
            tmdb_id: "778",
            title: "Sample Movie",
            in_library?: false
          }
        }
      }
    ]
  end
end
