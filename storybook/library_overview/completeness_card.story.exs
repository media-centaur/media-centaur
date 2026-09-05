defmodule MediaCentaurWeb.Storybook.LibraryOverview.CompletenessCard do
  @moduledoc """
  "Completeness gaps" card — missing artwork, missing metadata, and incomplete
  seasons. Counts go amber only when there is a gap. Takes a typed
  `MediaCentaur.Status.LibraryOverview`.
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Status.LibraryOverview

  def function, do: &MediaCentaurWeb.LibraryOverviewComponents.completeness_card/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :with_gaps,
        description: "All three gap kinds present — amber counters, deep-links.",
        attributes: %{
          overview:
            overview(
              missing_artwork_count: 12,
              missing_images: %{total: 0, missing: 12, by_role: %{}},
              missing_metadata_count: 3,
              incomplete_season_count: 5
            )
        }
      },
      %Variation{
        id: :one_gap,
        description: "Only one gap kind — the other rows still list at zero (muted).",
        attributes: %{overview: overview(missing_artwork_count: 4)}
      },
      %Variation{
        id: :no_gaps,
        description: "A complete library — the success summary line replaces the rows.",
        attributes: %{overview: overview([])}
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
