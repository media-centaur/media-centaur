defmodule MediaCentaurWeb.Storybook.Health.HealthDrillIn do
  @moduledoc """
  Story for the `<.health_drill_in>` component — the inline stacked subsystem
  detail (Summary → Activity → Issues → collapsed Logs, Phase 4 design P4-6).
  Covers the with-issues and healthy (empty-issues) states. The summary is
  derived from `view.component`; the Activity slot is supplied by the LiveView,
  so it's absent here.
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaurWeb.StatusLive.SubsystemView

  def function, do: &MediaCentaurWeb.HealthComponents.health_drill_in/1

  defp view(state) do
    %SubsystemView{
      component: :pipeline,
      label: "Import",
      glyph: "hero-arrow-down-tray",
      state: state,
      error_count: if(state == :error, do: 1, else: 0),
      warning_count: 0
    }
  end

  defp bucket do
    %Bucket{
      fingerprint: "fp",
      component: :pipeline,
      normalized_message: "image download failed",
      display_title: "Image downloads failing for 11 items",
      severity: :error,
      count: 11,
      first_seen: ~U[2026-06-01 14:02:00Z],
      last_seen: ~U[2026-06-01 15:00:00Z],
      sample_entries: [%{timestamp: ~U[2026-06-01 14:02:00Z], message: "TMDB image 503 for tt123"}]
    }
  end

  def variations do
    [
      %Variation{id: :with_issues, attributes: %{view: view(:error), buckets: [bucket()]}},
      %Variation{id: :healthy, attributes: %{view: view(:ok), buckets: []}}
    ]
  end
end
