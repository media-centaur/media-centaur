defmodule MediaCentarrWeb.Storybook.Acquisition.DecisionCard do
  @moduledoc "Alternatives picker shown on a pursuit detail page when its `awaiting_decision_at` flag is set."

  use PhoenixStorybook.Story, :component

  alias MediaCentarr.Acquisition.ViewModels.{Alternative, DecisionCard}

  def function, do: &MediaCentarrWeb.Components.Acquisition.DecisionCard.decision_card/1
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
        id: :loading,
        description: "Searching Prowlarr for fresh alternatives",
        attributes: %{
          vm: %DecisionCard{
            pursuit_id: "story-loading",
            prompt: "Download stalled for 24+ hours — pick an alternative release.",
            alternatives: [],
            loading?: true,
            search_queries: ["Sample Movie 2010"]
          },
          on_cancel: "noop"
        }
      },
      %Variation{
        id: :no_alternatives,
        description: "Search completed but Prowlarr returned no results",
        attributes: %{
          vm: %DecisionCard{
            pursuit_id: "story-empty",
            prompt: "Download stalled for 24+ hours.",
            alternatives: [],
            loading?: false,
            search_queries: ["Sample Movie 2010"]
          },
          on_cancel: "noop"
        }
      },
      %Variation{
        id: :one_alternative,
        description: "A single alternative — common case for less-popular titles",
        attributes: %{
          vm: %DecisionCard{
            pursuit_id: "story-one",
            prompt: "Download stalled for 24+ hours — pick an alternative release.",
            alternatives: [
              alternative(
                guid: "alt-1",
                title: "Sample.Movie.2010.1080p.WEB-DL.H264-NTG",
                indexer: "ExampleIndexer",
                quality: "1080p",
                size_bytes: 4_500_000_000,
                seeders: 25
              )
            ],
            loading?: false,
            search_queries: ["Sample Movie 2010"]
          },
          on_cancel: "noop"
        }
      },
      %Variation{
        id: :many_alternatives,
        description: "Multiple alternatives ranked by quality and seeder count",
        attributes: %{
          vm: %DecisionCard{
            pursuit_id: "story-many",
            prompt: "Download stalled for 24+ hours — pick an alternative release.",
            search_queries: ["Sample Show S01E03", "Sample Show Season 1"],
            alternatives: [
              alternative(
                guid: "alt-uhd",
                title: "Sample.Movie.2010.2160p.UHD.BluRay.REMUX-FGT",
                indexer: "ExampleIndexer",
                quality: "4K",
                size_bytes: 56_000_000_000,
                seeders: 8
              ),
              alternative(
                guid: "alt-1080",
                title: "Sample.Movie.2010.1080p.WEB-DL.H264-NTG",
                indexer: "ExampleIndexer",
                quality: "1080p",
                size_bytes: 4_500_000_000,
                seeders: 47
              ),
              alternative(
                guid: "alt-1080-blu",
                title: "Sample.Movie.2010.1080p.BluRay.x264-SPARKS",
                indexer: "AnotherIndexer",
                quality: "1080p",
                size_bytes: 8_200_000_000,
                seeders: 12
              ),
              alternative(
                guid: "alt-720",
                title: "Sample.Movie.2010.720p.BluRay.x264-AMIABLE",
                indexer: "ExampleIndexer",
                quality: "720p",
                size_bytes: 4_400_000_000,
                seeders: 33
              )
            ],
            loading?: false
          },
          on_cancel: "noop"
        }
      }
    ]
  end

  defp alternative(opts) do
    %Alternative{
      guid: Keyword.fetch!(opts, :guid),
      title: Keyword.fetch!(opts, :title),
      indexer: Keyword.fetch!(opts, :indexer),
      quality: Keyword.get(opts, :quality),
      size_bytes: Keyword.get(opts, :size_bytes),
      seeders: Keyword.get(opts, :seeders)
    }
  end
end
