defmodule MediaCentarrWeb.Storybook.Detail.MoreInfoPanel do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.Components.Detail.MoreInfoPanel.more_info_panel/1

  @cast Enum.map(0..7, fn i ->
          %{
            "name" => "Sample Actor #{i + 1}",
            "character" => "Sample Role #{i + 1}",
            "tmdb_person_id" => 1000 + i,
            "profile_path" => nil,
            "order" => i
          }
        end)

  @crew [
    %{
      "tmdb_person_id" => 1,
      "name" => "Sample Director",
      "job" => "Director",
      "department" => "Directing",
      "profile_path" => nil
    },
    %{
      "tmdb_person_id" => 2,
      "name" => "Sample Writer A",
      "job" => "Screenplay",
      "department" => "Writing",
      "profile_path" => nil
    },
    %{
      "tmdb_person_id" => 3,
      "name" => "Sample Writer B",
      "job" => "Story",
      "department" => "Writing",
      "profile_path" => nil
    }
  ]

  @entity %{
    type: :movie,
    name: "Sample Movie",
    url: "https://www.themoviedb.org/movie/1",
    imdb_id: "tt0000001",
    duration: "PT1H47M",
    date_published: "2025-08-15",
    studio: "Sample Studio",
    country_code: "US",
    original_language: "en",
    cast: @cast,
    crew: @crew
  }

  def variations do
    [
      %PhoenixStorybook.Variation{
        id: :default,
        attributes: %{entity: @entity}
      },
      %PhoenixStorybook.Variation{
        id: :no_imdb,
        description: "imdb_id missing — IMDb link is hidden",
        attributes: %{entity: %{@entity | imdb_id: nil}}
      },
      %PhoenixStorybook.Variation{
        id: :empty_credits,
        description: "no crew or cast — credit lines collapse, meta + links remain",
        attributes: %{entity: %{@entity | crew: [], cast: []}}
      }
    ]
  end
end
