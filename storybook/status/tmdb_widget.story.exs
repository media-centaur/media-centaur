defmodule MediaCentaurWeb.Storybook.Status.TmdbWidget do
  @moduledoc "Storybook coverage for the TMDB Activity widget (config + metadata-activity feed)."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.StatusWidgets.Tmdb.tmdb_widget/1

  def render_source, do: :function

  defp seconds_ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  defp empty_metadata, do: %{last_enriched_at: nil, total: 0, recent: []}

  def variations do
    [
      %Variation{
        id: :not_configured,
        attributes: %{
          config: %{tmdb_configured: false},
          metadata_stats: empty_metadata()
        }
      },
      %Variation{
        id: :configured_idle,
        attributes: %{
          config: %{tmdb_configured: true},
          metadata_stats: empty_metadata()
        }
      },
      %Variation{
        id: :recent_activity,
        attributes: %{
          config: %{tmdb_configured: true},
          metadata_stats: %{
            last_enriched_at: seconds_ago(180),
            total: 412,
            recent: [
              %{kind: :movie, title: "Sample Movie", year: 2024, at: seconds_ago(180)},
              %{kind: :tv_series, title: "Sample Show", year: 2022, at: seconds_ago(740)},
              %{kind: :movie_series, title: "Sample Collection", year: nil, at: seconds_ago(1_500)}
            ]
          }
        }
      },
      %Variation{
        id: :low_confidence,
        attributes: %{
          config: %{tmdb_configured: true},
          metadata_stats: %{
            last_enriched_at: seconds_ago(60),
            total: 88,
            recent: [%{kind: :movie, title: "Sample Movie", year: 2024, at: seconds_ago(60)}]
          },
          low_confidence_count: 3
        }
      }
    ]
  end
end
