defmodule MediaCentaurWeb.Storybook.Review.MatchResult do
  @moduledoc "One search result in Review's action bar; pressing it matches every ticked row."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.ReviewQueue.match_result/1
  def render_source, do: :function
  def template, do: ~s|<div class="w-[18rem]"><.psb-variation/></div>|

  def variations do
    [
      %Variation{
        id: :series,
        description: "A series, no poster",
        attributes: %{
          count: 6,
          result: %{
            tmdb_id: "4242",
            tmdb_type: "tv",
            title: "Sample Show",
            year: "1995",
            overview: nil,
            poster_path: nil
          }
        }
      },
      %Variation{
        id: :film_no_year,
        description: "A film with no year",
        attributes: %{
          count: 1,
          result: %{
            tmdb_id: "550",
            tmdb_type: "movie",
            title: "Movie A",
            year: nil,
            overview: nil,
            poster_path: nil
          }
        }
      }
    ]
  end
end
