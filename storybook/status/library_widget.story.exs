defmodule MediaCentaurWeb.Storybook.Status.LibraryWidget do
  @moduledoc """
  Library subsystem Activity widget — the "Your library" overview rendered in
  the health-board drill-in: glance (counts/size/recent), pending work,
  completeness gaps, and storage outlook.

  Composes the library-overview cards; see the `LibraryOverview/*` stories for
  the individual cards' state matrices.
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Status.LibraryOverview

  def function, do: &MediaCentaurWeb.Components.StatusWidgets.Library.library_widget/1
  def render_source, do: :function
  def layout, do: :one_column

  def variations do
    [
      %Variation{
        id: :populated,
        description: "A healthy library with recent additions and a couple of gaps.",
        attributes: %{
          overview:
            overview(
              recently_added: recent_items(8),
              missing_metadata_count: 3,
              incomplete_season_count: 2
            ),
          storage_drives: [drive("Database", "/var/lib/media-centaur", 63), drive("Media", "/media", 41)],
          at_risk_summary: %{},
          ttl_days: 30
        }
      },
      %Variation{
        id: :loading,
        description: "Overview still loading — the widget shows its loading line.",
        attributes: %{
          overview: nil,
          storage_drives: [],
          at_risk_summary: %{},
          ttl_days: 30
        }
      }
    ]
  end

  defp overview(overrides) do
    defaults = %{
      movie_count: 31,
      show_count: 18,
      episode_count: 508,
      total_size_bytes: 124_554_051_584,
      recently_added: [],
      pending_review_count: 136,
      in_flight_count: 3,
      missing_artwork_count: 0,
      missing_metadata_count: 0,
      incomplete_season_count: 0
    }

    struct!(LibraryOverview, Map.merge(defaults, Map.new(overrides)))
  end

  defp recent_items(count) do
    for i <- 1..count do
      %{
        id: "recent-#{i}",
        name: "Sample Title #{i}",
        year: Integer.to_string(1920 + i),
        poster_url: "https://placehold.co/200x300/1f2433/ffffff?text=#{i}"
      }
    end
  end

  defp drive(label, path, usage_percent) do
    total = 4_000_000_000_000
    used = round(total * usage_percent / 100)

    %{
      mount_point: path,
      device: "/dev/sample",
      used_bytes: used,
      total_bytes: total,
      usage_percent: usage_percent,
      roles: [%{label: label, path: path}]
    }
  end
end
