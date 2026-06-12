defmodule MediaCentaurWeb.Storybook.Acquisition.ConnectivityBadge do
  @moduledoc "Download-client connectivity notice for the Active Pursuits header — quiet when healthy, scoped warning only on a graded outage or auth failure."

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Acquisition.ConnectivityBadge.connectivity_badge/1
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
          "Quiet when healthy (live / initializing / transient blip / not-configured render nothing); a scoped warning only on a graded outage",
        variations: [
          %Variation{
            id: :live,
            description: "Last poll succeeded — renders nothing (no false 'live' next to pursuits)",
            attributes: %{connectivity: :live}
          },
          %Variation{
            id: :initializing,
            description: "No poll outcome yet — renders nothing (transient startup)",
            attributes: %{connectivity: :initializing}
          },
          %Variation{
            id: :transient_failure,
            description:
              "Exactly one failed poll — renders nothing (a blip between healthy polls is not an outage)",
            attributes: %{connectivity: {:transient_failure, ~U[2026-05-08 22:00:00Z]}}
          },
          %Variation{
            id: :offline,
            description:
              "Two or more consecutive failed polls — red outage notice dated from the first failure",
            attributes: %{connectivity: {:offline, ~U[2026-05-08 22:00:00Z]}}
          },
          %Variation{
            id: :auth_failed,
            description:
              "qBittorrent rejected our credentials — red warning with a Reconfigure call-to-action",
            attributes: %{connectivity: :auth_failed}
          },
          %Variation{
            id: :not_configured,
            description: "No download client configured — renders nothing (the page banner covers it)",
            attributes: %{connectivity: :not_configured}
          }
        ]
      }
    ]
  end
end
