defmodule MediaCentaurWeb.Storybook.Detail.MoreInfoPanel do
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Library.MediaTrackOverride
  alias MediaCentaur.Library.Person

  def function, do: &MediaCentaurWeb.Components.Detail.MoreInfoPanel.more_info_panel/1

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
        id: :movie_with_track_override,
        description:
          "Captured per-entity track override — 'Remembered tracks' badge with audio + subtitle languages and a Reset action",
        attributes: %{
          entity:
            Map.put(@entity, :track_override, %MediaTrackOverride{
              owner_type: :movie,
              owner_id: "00000000-0000-0000-0000-000000000001",
              audio_lang: "jpn",
              subtitle_lang: "eng"
            })
        }
      },
      %Variation{
        id: :movie_track_override_subs_off,
        description: "Override that disables subtitles for this entity — badge reads 'Subtitles off'",
        attributes: %{
          entity:
            Map.put(@entity, :track_override, %MediaTrackOverride{
              owner_type: :movie,
              owner_id: "00000000-0000-0000-0000-000000000002",
              audio_lang: "eng",
              subtitles_off: true
            })
        }
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
      },
      %Variation{
        id: :tv_series_with_track_override,
        description: "TV series with a forced-subtitle override — badge shows '(forced)' suffix",
        attributes: %{
          entity:
            Map.put(@tv_entity, :track_override, %MediaTrackOverride{
              owner_type: :tv_series,
              owner_id: "00000000-0000-0000-0000-000000000003",
              subtitle_lang: "eng",
              subtitle_forced: true
            })
        }
      }
    ]
  end
end
