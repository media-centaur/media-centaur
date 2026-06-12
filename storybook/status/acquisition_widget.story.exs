defmodule MediaCentaurWeb.Storybook.Status.AcquisitionWidget do
  @moduledoc "Storybook coverage for the Downloads Activity widget (connectivity + throughput)."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.ActivityWidgetComponents.acquisition_widget/1

  def render_source, do: :function

  def variations do
    throughput = %{acquired: 142, failed: 18, active: 3, success_rate: 89}

    [
      %Variation{
        id: :healthy,
        attributes: %{
          acquisition_activity: %{
            configured?: true,
            connectivity: :live,
            last_poll_at: ~U[2026-06-09 12:00:00.000000Z],
            prowlarr_ready?: true,
            throughput: throughput
          }
        }
      },
      %Variation{
        id: :client_retrying,
        description: "One failed poll — amber Retrying…, not yet a graded outage",
        attributes: %{
          acquisition_activity: %{
            configured?: true,
            connectivity: {:transient_failure, ~U[2026-06-09 11:59:50.000000Z]},
            last_poll_at: ~U[2026-06-09 11:59:40.000000Z],
            prowlarr_ready?: true,
            throughput: throughput
          }
        }
      },
      %Variation{
        id: :client_offline,
        attributes: %{
          acquisition_activity: %{
            configured?: true,
            connectivity: {:offline, ~U[2026-06-09 11:30:00.000000Z]},
            last_poll_at: ~U[2026-06-09 11:30:00.000000Z],
            prowlarr_ready?: true,
            throughput: throughput
          }
        }
      },
      %Variation{
        id: :prowlarr_unreachable,
        attributes: %{
          acquisition_activity: %{
            configured?: true,
            connectivity: :live,
            last_poll_at: ~U[2026-06-09 12:00:00.000000Z],
            prowlarr_ready?: false,
            throughput: %{acquired: 0, failed: 0, active: 0, success_rate: nil}
          }
        }
      },
      %Variation{
        id: :unconfigured,
        attributes: %{
          acquisition_activity: %{
            configured?: false,
            connectivity: :not_configured,
            last_poll_at: nil,
            prowlarr_ready?: false,
            throughput: %{acquired: 0, failed: 0, active: 0, success_rate: nil}
          }
        }
      }
    ]
  end
end
