defmodule MediaCentaurWeb.Storybook.Acquisition.PursuitHeader do
  @moduledoc """
  The pursuit window's pinned identity: lockup (logo or logotype), state
  word, and the meta line — type, the goal's scope over its units, criteria.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.Pursuits.Recipe
  alias MediaCentaur.Acquisition.ViewModels.PursuitHeader

  def function, do: &MediaCentaurWeb.Components.Acquisition.PursuitHeader.pursuit_header/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-2xl rounded-xl bg-base-300 pt-6">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :tv_with_logo,
        description:
          "A series goal with a cached logo — the PNG replaces the text title in the lockup " <>
            "(inline SVG stand-in; real assets come from /media-images). The scope spans the units.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-hero",
            title: "Sample Show",
            state: :active,
            logo_url:
              "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='400' height='90'><text x='0' y='64' font-family='sans-serif' font-size='56' font-weight='800' letter-spacing='6' fill='white'>SAMPLE SHOW</text></svg>",
            recipe: %Recipe{
              type: :tmdb,
              title: "Sample Show",
              tmdb_type: :tv,
              tmdb_id: "10",
              season_number: 1
            },
            scope_label: "5 seasons · 30 episodes",
            criteria_summary: "1080p or better, up to 4K"
          }
        }
      },
      %Variation{
        id: :movie_with_year,
        description: "A film: the scope is its year.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-movie",
            title: "Sample Movie",
            state: :active,
            recipe: %Recipe{type: :tmdb, title: "Sample Movie", tmdb_type: :movie, year: 2010},
            scope_label: "2010"
          }
        }
      },
      %Variation{
        id: :tv_episode,
        description: "One episode: the scope is its code.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-episode",
            title: "Sample Show",
            state: :active,
            recipe: %Recipe{
              type: :tmdb,
              title: "Sample Show",
              tmdb_type: :tv,
              season_number: 1,
              episode_number: 4
            },
            scope_label: "S01E04"
          }
        }
      },
      %Variation{
        id: :one_season,
        description: "One season of a series: the season and its episode count.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-season",
            title: "Sample Show",
            state: :partial,
            recipe: %Recipe{type: :tmdb, title: "Sample Show", tmdb_type: :tv, season_number: 4},
            scope_label: "Season 4 · 6 episodes"
          }
        }
      },
      %Variation{
        id: :manual_query,
        description: "A Prowlarr-query goal: the query is the identity, there is no scope.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-manual",
            title: "Phantom of the Opera (1925) · 1080p WEB-DL",
            state: :active,
            recipe: %Recipe{
              type: :prowlarr_query,
              title: "Phantom of the Opera (1925) · 1080p WEB-DL",
              manual_query: "Phantom of the Opera 1925"
            }
          }
        }
      },
      %Variation{
        id: :awaiting_decision,
        description: "Awaiting a pick: the state badge is the call to action.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-decision",
            title: "Sample Show",
            state: :active,
            awaiting_decision?: true,
            recipe: %Recipe{
              type: :tmdb,
              title: "Sample Show",
              tmdb_type: :tv,
              season_number: 1,
              episode_number: 4
            },
            scope_label: "S01E04"
          }
        }
      },
      %Variation{
        id: :terminal_satisfied,
        description: "Done.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-done",
            title: "Sample Movie",
            state: :satisfied,
            recipe: %Recipe{type: :tmdb, title: "Sample Movie", tmdb_type: :movie, year: 2010},
            scope_label: "2010"
          }
        }
      },
      %Variation{
        id: :terminal_exhausted,
        description: "Gave up.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-gave-up",
            title: "Sample Movie",
            state: :exhausted,
            recipe: %Recipe{type: :tmdb, title: "Sample Movie", tmdb_type: :movie, year: 2010},
            scope_label: "2010"
          }
        }
      }
    ]
  end
end
