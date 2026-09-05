defmodule MediaCentaurWeb.Storybook.LibraryOverview.PendingWorkCard do
  @moduledoc """
  "Pending work" card — review backlog and in-flight acquisitions, each
  linking to its surface. Takes a typed `MediaCentaur.Status.LibraryOverview`.
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Status.LibraryOverview

  def function, do: &MediaCentaurWeb.LibraryOverviewComponents.pending_work_card/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :backlog,
        description: "Files awaiting review (amber) and acquisitions in flight.",
        attributes: %{overview: overview(pending_review_count: 6, in_flight_count: 2)}
      },
      %Variation{
        id: :single_each,
        description: "Singular pluralisation — one of each.",
        attributes: %{overview: overview(pending_review_count: 1, in_flight_count: 1)}
      },
      %Variation{
        id: :all_clear,
        description: "Nothing pending — both rows show their muted empty state.",
        attributes: %{overview: overview(pending_review_count: 0, in_flight_count: 0)}
      }
    ]
  end

  defp overview(overrides) do
    defaults = %{
      movie_count: 0,
      show_count: 0,
      episode_count: 0,
      total_size_bytes: 0,
      recently_added: [],
      pending_review_count: 0,
      in_flight_count: 0,
      missing_artwork_count: 0,
      missing_images: %{total: 0, missing: 0, by_role: %{}},
      missing_metadata_count: 0,
      incomplete_season_count: 0
    }

    struct!(LibraryOverview, Map.merge(defaults, Map.new(overrides)))
  end
end
