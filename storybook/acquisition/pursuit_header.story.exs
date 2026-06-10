defmodule MediaCentaurWeb.Storybook.Acquisition.PursuitHeader do
  @moduledoc "Identity header for the pursuit detail modal."

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.ViewModels.PursuitHeader
  alias MediaCentaur.Acquisition.ViewModels.Recipe

  def function, do: &MediaCentaurWeb.Components.Acquisition.PursuitHeader.pursuit_header/1
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
        id: :tv_with_backdrop_and_logo,
        description:
          "TMDB pursuit with cached artwork — the backdrop is the panel background, the logo PNG replaces the text title, and type/state/queries sit on the scrim (UIDR-011/014). Inline SVG stand-ins; real assets come from /media-images.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-hero",
            title: "Sample Show",
            state: :active,
            backdrop_url:
              "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='1280' height='720'><defs><linearGradient id='g' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='%23355070'/><stop offset='1' stop-color='%23172033'/></linearGradient></defs><rect width='1280' height='720' fill='url(%23g)'/><circle cx='980' cy='180' r='240' fill='%236d8cb0' opacity='0.35'/></svg>",
            logo_url:
              "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='400' height='90'><text x='0' y='64' font-family='sans-serif' font-size='56' font-weight='800' letter-spacing='6' fill='white'>SAMPLE SHOW</text></svg>",
            recipe: %Recipe{
              recipe_type: :tmdb,
              tmdb_type: "tv",
              tmdb_id: "10",
              season_number: 1,
              search_queries: ["Sample Show Season 1", "Sample Show S01"]
            },
            criteria_summary: "min_quality: 1080p"
          }
        }
      },
      %Variation{
        id: :movie_with_year,
        description: "Movie pursuit, no cached artwork — synthetic gradient + logotype fallback",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-movie",
            title: "Public Domain Feature 1925",
            state: :active,
            recipe: %Recipe{
              recipe_type: :tmdb,
              tmdb_type: "movie",
              tmdb_id: "1",
              year: 1925,
              search_queries: ["Public Domain Feature 1925"]
            },
            criteria_summary: "max_quality: 2160p, min_quality: 1080p"
          }
        }
      },
      %Variation{
        id: :tv_episode,
        description: "TV episode pursuit, no cached artwork — fallback hero, queries on the scrim",
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
              episode_number: 3,
              search_queries: ["Sample Show S01E03", "Sample Show Season 1"]
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
              manual_query: "Phantom of the Opera 1925",
              search_queries: ["Phantom of the Opera 1925"]
            },
            criteria_summary: nil
          }
        }
      },
      %Variation{
        id: :manual_query_expanded,
        description: "Prowlarr query with brace expansion — multiple queries",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-manual-expanded",
            title: "Sample Show S01E{01,02,03}",
            state: :active,
            recipe: %Recipe{
              recipe_type: :prowlarr_query,
              manual_query: "Sample Show S01E{01,02,03}",
              search_queries: [
                "Sample Show S01E01",
                "Sample Show S01E02",
                "Sample Show S01E03"
              ]
            },
            criteria_summary: nil
          }
        }
      },
      %Variation{
        id: :awaiting_decision,
        description: "Pursuit awaiting user decision (state :active, flag set)",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-decision",
            title: "Sample Show S01E04",
            state: :active,
            awaiting_decision?: true,
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
