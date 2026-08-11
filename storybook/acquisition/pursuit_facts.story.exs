defmodule MediaCentaurWeb.Storybook.Acquisition.PursuitFacts do
  @moduledoc """
  The pursuit's search facts, seated at the top of the modal body: the
  release-filename subtitle (Prowlarr-query pursuits that already
  picked a release) and the literal indexer queries — "Searching
  Prowlarr" should never be abstract; the user can compare these
  strings to what they'd paste into Prowlarr by hand.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.Pursuits.Recipe
  alias MediaCentaur.Acquisition.ViewModels.PursuitHeader

  def function, do: &MediaCentaurWeb.Components.Acquisition.PursuitHeader.pursuit_facts/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-2xl glass-inset rounded-xl p-6">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :tmdb_queries,
        description: "TMDB pursuit — the queries QueryBuilder runs, one per line.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-tmdb",
            title: "Sample Show",
            state: :active,
            recipe: %Recipe{type: :tmdb, title: "Sample Show", tmdb_type: :tv, season_number: 1},
            search_queries: ["Sample Show Season 1", "Sample Show S01"]
          }
        }
      },
      %Variation{
        id: :manual_query_with_release,
        description:
          "Prowlarr-query pursuit after a pick — the release filename is a demoted " <>
            "monospace subtitle above the query list.",
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
            search_queries: ["Phantom of the Opera 1925"]
          }
        }
      },
      %Variation{
        id: :brace_expanded,
        description: "Brace-expanded Prowlarr query — multiple literal queries.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-expanded",
            title: "Sample Show S01E{01,02,03}",
            state: :active,
            recipe: %Recipe{
              type: :prowlarr_query,
              title: "Sample Show S01E{01,02,03}",
              manual_query: "Sample Show S01E{01,02,03}"
            },
            search_queries: [
              "Sample Show S01E01",
              "Sample Show S01E02",
              "Sample Show S01E03"
            ]
          }
        }
      },
      %Variation{
        id: :nothing_to_show,
        description: "No queries, no release subtitle — the component renders nothing.",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-empty",
            title: "Movie A",
            state: :satisfied,
            recipe: %Recipe{type: :tmdb, title: "Movie A", tmdb_type: :movie},
            search_queries: []
          }
        }
      }
    ]
  end
end
