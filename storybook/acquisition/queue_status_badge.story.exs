defmodule MediaCentaurWeb.Storybook.Acquisition.QueueStatusBadge do
  @moduledoc "Download-client connectivity notice for the Active Pursuits header — quiet when healthy, scoped warning when degraded."

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Acquisition.QueueStatusBadge.queue_status_badge/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-md">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %VariationGroup{
        id: :all_states,
        description:
          "Quiet when healthy (live / initializing / not-configured render nothing); a scoped warning only when degraded",
        variations: [
          %Variation{
            id: :live,
            description:
              "Healthy poll within 2× cadence — renders nothing (no false 'live' next to pursuits)",
            attributes: %{status: :live}
          },
          %Variation{
            id: :initializing,
            description: "No successful poll yet, no error — renders nothing (transient startup)",
            attributes: %{status: :initializing}
          },
          %Variation{
            id: :lagging,
            description: "Telemetry 4.2 s stale (between 2× and 5× cadence) — amber 'lagging' warning",
            attributes: %{status: {:lagging, 4_200}}
          },
          %Variation{
            id: :offline,
            description: "Connection lost — red 'offline' warning with last-update age",
            attributes: %{status: {:offline, ~U[2026-05-08 22:00:00Z]}}
          },
          %Variation{
            id: :auth_failed,
            description:
              "qBittorrent rejected our credentials — red warning with a Reconfigure call-to-action",
            attributes: %{status: :auth_failed}
          },
          %Variation{
            id: :not_configured,
            description: "No download client configured — renders nothing (the page banner covers it)",
            attributes: %{status: :not_configured}
          }
        ]
      }
    ]
  end
end
