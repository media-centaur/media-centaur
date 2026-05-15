defmodule MediaCentarrWeb.Storybook.Detail.MoreInfoPanel do
  use PhoenixStorybook.Story, :component

  alias MediaCentarr.Library.Person

  def function, do: &MediaCentarrWeb.Components.Detail.MoreInfoPanel.more_info_panel/1

  @cast Enum.map(0..7, fn i ->
          %Person{
            name: "Sample Actor #{i + 1}",
            character: "Sample Role #{i + 1}",
            tmdb_person_id: 1000 + i,
            profile_path: nil,
            order: i
          }
        end)

  @crew [
    %Person{
      tmdb_person_id: 1,
      name: "Sample Director",
      job: "Director",
      department: "Directing",
      profile_path: nil
    },
    %Person{
      tmdb_person_id: 2,
      name: "Sample Writer A",
      job: "Screenplay",
      department: "Writing",
      profile_path: nil
    },
    %Person{
      tmdb_person_id: 3,
      name: "Sample Writer B",
      job: "Story",
      department: "Writing",
      profile_path: nil
    }
  ]

  @entity %{
    type: :movie,
    name: "Sample Movie",
    url: "https://www.themoviedb.org/movie/1",
    imdb_id: "tt0000001",
    duration_seconds: 6420,
    date_published: ~D[2025-08-15],
    studio: "Sample Studio",
    country_code: "US",
    original_language: "en",
    cast: @cast,
    crew: @crew
  }

  @creators [
    %Person{
      tmdb_person_id: 11,
      name: "Sample Creator A",
      job: "Creator",
      department: "Creator",
      profile_path: nil
    },
    %Person{
      tmdb_person_id: 12,
      name: "Sample Creator B",
      job: "Creator",
      department: "Creator",
      profile_path: nil
    }
  ]

  @tv_entity %{
    type: :tv_series,
    name: "Sample Series",
    url: "https://www.themoviedb.org/tv/1",
    imdb_id: "tt0000200",
    date_published: ~D[2020-01-15],
    network: "Sample Network",
    status: :returning,
    country_code: "US",
    original_language: "en",
    cast: @cast,
    crew: @creators
  }

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{entity: @entity}
      },
      %Variation{
        id: :no_imdb,
        description: "imdb_id missing — IMDb link is hidden",
        attributes: %{entity: %{@entity | imdb_id: nil}}
      },
      %Variation{
        id: :empty_credits,
        description: "no crew or cast — credit lines collapse, meta + links remain",
        attributes: %{entity: %{@entity | crew: [], cast: []}}
      },
      %Variation{
        id: :tv_series,
        description: "TV series — Created by row, aggregate cast, network/first-aired/status meta",
        attributes: %{entity: @tv_entity}
      },
      %Variation{
        id: :tv_series_empty_credits,
        description: "TV series with no creators or cast — meta + links still render",
        attributes: %{entity: %{@tv_entity | crew: [], cast: []}}
      }
    ]
  end
end
