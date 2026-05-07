defmodule MediaCentarrWeb.Storybook.Acquisition.PursuitTimeline do
  @moduledoc "Full-page timeline rendering all events for a pursuit."

  use PhoenixStorybook.Story, :component

  alias MediaCentarr.Acquisition.ViewModels.{Timeline, TimelineEntry}

  def function, do: &MediaCentarrWeb.Components.Acquisition.PursuitTimeline.timeline/1
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
        id: :mixed_kinds,
        description: "Timeline showing every severity level across a pursuit's history",
        attributes: %{vm: %Timeline{pursuit_id: "story-mixed", entries: mixed_entries()}}
      },
      %Variation{
        id: :empty,
        description: "Pursuit has no events yet (just-created)",
        attributes: %{vm: %Timeline{pursuit_id: "story-empty", entries: []}}
      },
      %Variation{
        id: :stall_to_satisfied,
        description: "Realistic 'stalled then user picked alternative then verified' flow",
        attributes: %{vm: %Timeline{pursuit_id: "story-flow", entries: stall_to_satisfied()}}
      }
    ]
  end

  defp ago(seconds), do: DateTime.add(~U[2026-05-08 12:00:00Z], -seconds)

  defp mixed_entries do
    [
      entry("pursuit_satisfied", "Pursuit satisfied", :success, ago(60)),
      entry("identity_verified", "Identity verified", :success, ago(120)),
      entry("download_started", "Download started", :info, ago(180)),
      entry("user_decision_recorded", "User picked — Sample.Movie.2010.1080p", :info, ago(300)),
      entry("user_decision_requested", "User decision requested", :info, ago(600)),
      entry("stall_confirmed", "Stall confirmed", :warning, ago(86_400)),
      entry("zero_seeders_confirmed", "Zero seeders confirmed", :warning, ago(43_200)),
      entry("identity_mismatch", "Identity mismatch — file routed to Review", :error, ago(108_000)),
      entry("pursuit_started", "Pursuit started (auto)", :info, ago(259_200))
    ]
  end

  defp stall_to_satisfied do
    [
      entry("pursuit_satisfied", "Pursuit satisfied", :success, ago(60)),
      entry("identity_verified", "Identity verified", :success, ago(120),
        detail: "/library/incoming/Sample.Movie.2010.1080p.mkv"
      ),
      entry("download_started", "Download started", :info, ago(180)),
      entry(
        "release_picked",
        "Release picked — Sample.Movie.2010.1080p.WEB-DL",
        :success,
        ago(300),
        detail: "ExampleIndexer • 1080p"
      ),
      entry("user_decision_recorded", "User picked alternative", :info, ago(360)),
      entry("user_decision_requested", "User decision requested", :info, ago(86_400)),
      entry("stall_confirmed", "Stall confirmed", :warning, ago(172_800)),
      entry(
        "release_picked",
        "Release picked — Sample.Movie.2010.2160p.UHD.BluRay (which later stalled)",
        :success,
        ago(259_200),
        detail: "ExampleIndexer • 2160p"
      ),
      entry("pursuit_started", "Pursuit started (auto)", :info, ago(259_300))
    ]
  end

  defp entry(kind, summary, severity, occurred_at, opts \\ []) do
    %TimelineEntry{
      kind: kind,
      occurred_at: occurred_at,
      summary: summary,
      severity: severity,
      detail: Keyword.get(opts, :detail)
    }
  end
end
