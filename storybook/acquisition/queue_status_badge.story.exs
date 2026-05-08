defmodule MediaCentarrWeb.Storybook.Acquisition.QueueStatusBadge do
  @moduledoc "Compact freshness pill for the Downloads page queue header."

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.Components.Acquisition.QueueStatusBadge.queue_status_badge/1
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
        description: "Each freshness/error grade rendered as a compact pill",
        variations: [
          %Variation{
            id: :live,
            description: "Recent successful poll within 2× cadence — feels real-time",
            attributes: %{status: :live}
          },
          %Variation{
            id: :initializing,
            description: "No successful poll yet, no error — startup or post-reconfigure",
            attributes: %{status: :initializing}
          },
          %Variation{
            id: :lagging,
            description: "Last successful poll 4 s ago at 1.5 s cadence — between 2× and 5×",
            attributes: %{status: {:lagging, 4_200}}
          },
          %Variation{
            id: :offline,
            description: "Connection lost — last successful poll 90 s ago",
            attributes: %{status: {:offline, ~U[2026-05-08 22:00:00Z]}}
          },
          %Variation{
            id: :auth_failed,
            description: "qBittorrent rejected our credentials. Reconfigure link is the call-to-action.",
            attributes: %{status: :auth_failed}
          },
          %Variation{
            id: :not_configured,
            description: "No download client configured at all",
            attributes: %{status: :not_configured}
          }
        ]
      }
    ]
  end
end
