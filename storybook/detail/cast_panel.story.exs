defmodule MediaCentaurWeb.Storybook.Detail.CastPanel do
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Library.Person

  def function, do: &MediaCentaurWeb.Components.Detail.CastPanel.cast_panel/1

  @movie_cast Enum.map(0..7, fn index ->
                %Person{
                  name: "Sample Actor #{index}",
                  character: "Sample Role #{index}",
                  tmdb_person_id: 1000 + index,
                  profile_path: nil,
                  order: index
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
    cast: @movie_cast,
    crew: @crew
  }

  # Series cast with appearance counts — enough entries that the second
  # section overflows one page and shows the disclosure.
  @series_cast Enum.map(0..29, fn index ->
                 %Person{
                   name: "Sample Actor #{index}",
                   character: "Sample Role #{index}",
                   tmdb_person_id: 1000 + index,
                   profile_path: nil,
                   order: index,
                   total_episode_count: 60 - index
                 }
               end)

  @tv_series %{
    type: :tv_series,
    name: "Sample Series",
    cast: @series_cast,
    crew: [],
    seasons: [
      %{
        season_number: 1,
        episodes: [
          %{
            episode_number: 1,
            content_url: "/tv/sample/s01e01.mkv",
            # Lead with a few members incl. a low-billed guest, so the
            # partition (not billing order) visibly decides the sections.
            cast_person_ids: [1000, 1002, 1025]
          }
        ]
      }
    ]
  }

  def variations do
    [
      %Variation{
        id: :movie,
        description: "Movie — Directed by / Written by headline above one billing-ordered grid.",
        attributes: %{entity: @movie}
      },
      %Variation{
        id: :movie_no_crew,
        description: "Movie without crew credits — the headline collapses, grid alone.",
        attributes: %{entity: %{@movie | crew: []}}
      },
      %Variation{
        id: :tv_partitioned,
        description:
          "TV series with episode membership — the cast of the episode Play " <>
            "would start leads under its own episode heading (*Season 1, Episode 1*), " <>
            "the rest under *Other episodes* with the Show more disclosure.",
        attributes: %{entity: @tv_series, resume_episode_key: {1, 1}}
      },
      %Variation{
        id: :tv_no_membership,
        description:
          "TV series without episode membership data (pre-backfill library) — " <>
            "degrades to a single appearance-ordered list.",
        attributes: %{entity: %{@tv_series | seasons: []}}
      },
      %Variation{
        id: :tv_filtered,
        description:
          "An active filter flattens the sections into one filtered list — " <>
            "filtering searches the whole cast.",
        attributes: %{entity: @tv_series, resume_episode_key: {1, 1}, cast_filter: "Actor 2"}
      },
      %Variation{
        id: :empty_cast,
        description: "No cast at all — the whole panel renders nothing visible.",
        attributes: %{entity: %{@tv_series | cast: [], seasons: []}}
      }
    ]
  end
end
