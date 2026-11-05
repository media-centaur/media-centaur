defmodule MediaCentaurWeb.Storybook.Acquisition.PursuitFacts do
  @moduledoc """
  The goal's facts under the header: who started it, when, how long it
  ran, how many releases it tried, how it ended — and, for a
  Prowlarr-query goal that picked a release, the release filename above
  them.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.Pursuits.Recipe
  alias MediaCentaur.Acquisition.ViewModels.PursuitHeader

  def function, do: &MediaCentaurWeb.Components.Acquisition.PursuitHeader.pursuit_facts/1
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
        id: :series_facts,
        description: "A series Auto-grab started, cancelled by hand after a night of retries.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-series",
            title: "Sample Show",
            state: :partial,
            recipe: %Recipe{type: :tmdb, title: "Sample Show", tmdb_type: :tv},
            facts: [
              "Auto-grab started this",
              "4 Nov 11:45",
              "ran 13h 42m",
              "252 releases tried",
              "ended 5 Nov 01:27"
            ]
          }
        }
      },
      %Variation{
        id: :film_in_flight,
        description: "A film you started, still running: no end yet.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-film",
            title: "Sample Movie",
            state: :active,
            recipe: %Recipe{type: :tmdb, title: "Sample Movie", tmdb_type: :movie, year: 2010},
            facts: ["You started this", "5 Nov 09:12", "ran 14m", "1 release tried"]
          }
        }
      },
      %Variation{
        id: :manual_query_with_release,
        description:
          "A Prowlarr-query goal after a pick — the release filename is a demoted monospace " <>
            "line above the facts.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-manual",
            title: "Phantom.of.the.Opera.1925.1080p.WEB-DL",
            state: :satisfied,
            recipe: %Recipe{
              type: :prowlarr_query,
              title: "Phantom.of.the.Opera.1925.1080p.WEB-DL",
              manual_query: "Phantom of the Opera 1925"
            },
            facts: ["You started this", "2 Nov 20:03", "ran 41m", "1 release tried", "done 2 Nov 20:44"]
          }
        }
      },
      %Variation{
        id: :nothing_to_show,
        description: "No facts and no release subtitle — the block renders nothing.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-empty",
            title: "Sample Movie",
            state: :active,
            recipe: %Recipe{type: :tmdb, title: "Sample Movie", tmdb_type: :movie},
            facts: []
          }
        }
      }
    ]
  end
end
