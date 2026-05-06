defmodule MediaCentarrWeb.Storybook.Detail.MoreInfo.ExternalLinks do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.Components.Detail.MoreInfo.ExternalLinks.external_links/1

  def variations do
    [
      %Variation{
        id: :tmdb_and_imdb,
        description: "Both TMDB and IMDb — the typical state for a fully-credited title.",
        attributes: %{
          tmdb_url: "https://www.themoviedb.org/movie/1",
          imdb_id: "tt0000001"
        }
      },
      %Variation{
        id: :tmdb_only,
        description: "IMDb id is missing (common for TV series with no `external_ids.imdb_id`).",
        attributes: %{
          tmdb_url: "https://www.themoviedb.org/tv/1",
          imdb_id: nil
        }
      },
      %Variation{
        id: :nothing,
        description: "Neither URL nor id — both links collapse, the row stays blank.",
        attributes: %{tmdb_url: nil, imdb_id: nil}
      }
    ]
  end
end
