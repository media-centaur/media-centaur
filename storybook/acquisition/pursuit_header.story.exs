defmodule MediaCentaurWeb.Storybook.Acquisition.PursuitHeader do
  @moduledoc """
  Pinned identity for the pursuit modal — the content of the cinematic
  frame's `:orientation` slot: the `TitleLayer.lockup` (logo PNG when
  the artwork cache has one, logotype fallback), the state badge, and
  one meta line (type icon + label, scope, criteria). The frame itself
  supplies the backdrop; the header only reads `logo_url`.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.Pursuits.Recipe
  alias MediaCentaur.Acquisition.ViewModels.PursuitHeader

  def function, do: &MediaCentaurWeb.Components.Acquisition.PursuitHeader.pursuit_header/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-2xl glass-inset rounded-xl py-6">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :tv_with_logo,
        description:
          "TMDB pursuit with a cached logo — the PNG replaces the text title in the lockup " <>
            "(inline SVG stand-in; real assets come from /media-images).",
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
            search_queries: ["Sample Show Season 1", "Sample Show S01"],
            criteria_summary: "min_quality: 1080p"
          }
        }
      },
      %Variation{
        id: :movie_with_year,
        description: "Movie pursuit, no cached logo — logotype fallback, year on the meta line.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-movie",
            title: "Public Domain Feature 1925",
            state: :active,
            recipe: %Recipe{
              type: :tmdb,
              title: "Public Domain Feature 1925",
              tmdb_type: :movie,
              tmdb_id: "1",
              year: 1925
            },
            search_queries: ["Public Domain Feature 1925"],
            criteria_summary: "max_quality: 2160p, min_quality: 1080p"
          }
        }
      },
      %Variation{
        id: :tv_episode,
        description: "TV episode pursuit — SxxExx scope on the meta line.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-tv",
            title: "Sample Show S01E03",
            state: :active,
            recipe: %Recipe{
              type: :tmdb,
              title: "Sample Show",
              tmdb_type: :tv,
              tmdb_id: "10",
              season_number: 1,
              episode_number: 3
            },
            search_queries: ["Sample Show S01E03", "Sample Show Season 1"],
            criteria_summary: nil
          }
        }
      },
      %Variation{
        id: :manual_query,
        description:
          "Free-form Prowlarr query pursuit — the typed query is the identity (logotype), " <>
            "the meta line reads Prowlarr query.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-manual",
            title: "Phantom of the Opera (1925) · 1080p WEB-DL",
            state: :active,
            recipe: %Recipe{
              type: :prowlarr_query,
              title: "Phantom of the Opera (1925) · 1080p WEB-DL",
              manual_query: "Phantom of the Opera 1925"
            },
            search_queries: ["Phantom of the Opera 1925"],
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
              type: :tmdb,
              title: "Sample Show",
              tmdb_type: :tv,
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
            recipe: %Recipe{type: :tmdb, title: "Movie A", tmdb_type: :movie, year: 2023},
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
            recipe: %Recipe{type: :tmdb, title: "Movie B", tmdb_type: :movie},
            criteria_summary: nil
          }
        }
      }
    ]
  end
end
