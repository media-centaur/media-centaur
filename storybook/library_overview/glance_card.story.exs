defmodule MediaCentaurWeb.Storybook.LibraryOverview.GlanceCard do
  @moduledoc """
  "At a glance" card for the Status page library overview — headline counts,
  size on disk, and a recently-added poster strip.

  Takes a typed `MediaCentaur.Status.LibraryOverview` struct.
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Status.LibraryOverview

  def function, do: &MediaCentaurWeb.LibraryOverviewComponents.glance_card/1
  def render_source, do: :function
  def layout, do: :one_column

  def variations do
    [
      %Variation{
        id: :populated,
        description: "A healthy library with counts, size, and recent posters.",
        attributes: %{overview: overview(recently_added: recent_items(8, posters: true))}
      },
      %Variation{
        id: :recent_fallback,
        description: "Recently-added items with no artwork — name overlay fallback renders.",
        attributes: %{overview: overview(recently_added: recent_items(4, posters: false))}
      },
      %Variation{
        id: :empty_library,
        description: "Empty library — zeroed counts and no recent strip.",
        attributes: %{
          overview:
            overview(
              movie_count: 0,
              show_count: 0,
              episode_count: 0,
              total_size_bytes: 0,
              recently_added: []
            )
        }
      }
    ]
  end

  defp overview(overrides) do
    defaults = %{
      movie_count: 128,
      show_count: 37,
      episode_count: 1042,
      total_size_bytes: 3_456_789_012_345,
      recently_added: [],
      pending_review_count: 0,
      in_flight_count: 0,
      missing_artwork_count: 0,
      missing_metadata_count: 0,
      incomplete_season_count: 0
    }

    struct!(LibraryOverview, Map.merge(defaults, Map.new(overrides)))
  end

  defp recent_items(count, posters: posters?) do
    for i <- 1..count do
      %{
        id: "recent-#{i}",
        name: "Sample Title #{i}",
        year: Integer.to_string(1920 + i),
        poster_url: if(posters?, do: "https://placehold.co/200x300/1f2433/ffffff?text=#{i}")
      }
    end
  end
end
