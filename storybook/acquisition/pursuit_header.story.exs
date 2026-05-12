defmodule MediaCentarrWeb.Storybook.Acquisition.PursuitHeader do
  @moduledoc "Identity header for the pursuit detail modal."

  use PhoenixStorybook.Story, :component

  alias MediaCentarr.Acquisition.ViewModels.PursuitHeader
  alias MediaCentarr.Acquisition.ViewModels.Recipe

  def function, do: &MediaCentarrWeb.Components.Acquisition.PursuitHeader.pursuit_header/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-2xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :movie_with_year,
        description: "Movie pursuit with year and 1080–4K criteria",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-movie",
            title: "Public Domain Feature 1925",
            state: :active,
            recipe: %Recipe{recipe_type: :tmdb, tmdb_type: "movie", tmdb_id: "1", year: 1925},
            criteria_summary: "max_quality: 2160p, min_quality: 1080p"
          }
        }
      },
      %Variation{
        id: :tv_episode,
        description: "TV episode pursuit",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-tv",
            title: "Sample Show S01E03",
            state: :active,
            recipe: %Recipe{
              recipe_type: :tmdb,
              tmdb_type: "tv",
              tmdb_id: "10",
              season_number: 1,
              episode_number: 3
            },
            criteria_summary: nil
          }
        }
      },
      %Variation{
        id: :manual_query,
        description: "Free-form Prowlarr query pursuit",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-manual",
            title: "Phantom of the Opera (1925) · 1080p WEB-DL",
            state: :active,
            recipe: %Recipe{
              recipe_type: :prowlarr_query,
              manual_query: "Phantom of the Opera 1925"
            },
            criteria_summary: nil
          }
        }
      },
      %Variation{
        id: :needs_decision,
        description: "Pursuit in needs_decision",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-decision",
            title: "Sample Show S01E04",
            state: :needs_decision,
            recipe: %Recipe{
              recipe_type: :tmdb,
              tmdb_type: "tv",
              season_number: 1,
              episode_number: 4
            },
            criteria_summary: nil
          }
        }
      },
      %Variation{
        id: :terminal_satisfied,
        attributes: %{
          vm: %PursuitHeader{
            id: "story-satisfied",
            title: "Movie A",
            state: :satisfied,
            recipe: %Recipe{recipe_type: :tmdb, tmdb_type: "movie", year: 2023},
            criteria_summary: nil
          }
        }
      },
      %Variation{
        id: :terminal_exhausted,
        attributes: %{
          vm: %PursuitHeader{
            id: "story-exhausted",
            title: "Movie B",
            state: :exhausted,
            recipe: %Recipe{recipe_type: :tmdb, tmdb_type: "movie"},
            criteria_summary: nil
          }
        }
      }
    ]
  end
end
