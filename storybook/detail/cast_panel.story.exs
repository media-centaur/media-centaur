defmodule MediaCentaurWeb.Storybook.Detail.CastPanel do
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Library.Person

  def function, do: &MediaCentaurWeb.Components.Detail.CastPanel.cast_panel/1

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

  @movie %{
    type: :movie,
    name: "Sample Movie",
    cast: @cast,
    crew: @crew
  }

  @tv_series %{
    type: :tv_series,
    name: "Sample Series",
    cast: @cast,
    crew: []
  }

  def variations do
    [
      %Variation{
        id: :movie,
        description: "Movie — Directed by / Written by headline above the cast grid.",
        attributes: %{entity: @movie}
      },
      %Variation{
        id: :movie_no_crew,
        description: "Movie without crew credits — the headline collapses, grid alone.",
        attributes: %{entity: %{@movie | crew: []}}
      },
      %Variation{
        id: :tv_series,
        description:
          "TV series — the grid alone. Per-episode directors/writers are " <>
            "deliberately not surfaced (TMDB aggregate crew is too noisy for " <>
            "a show-level row).",
        attributes: %{entity: @tv_series}
      },
      %Variation{
        id: :empty_cast,
        description: "No cast at all — the whole panel renders nothing visible.",
        attributes: %{entity: %{@tv_series | cast: []}}
      }
    ]
  end
end
