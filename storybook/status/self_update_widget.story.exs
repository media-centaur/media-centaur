defmodule MediaCentaurWeb.Storybook.Status.SelfUpdateWidget do
  @moduledoc "Storybook coverage for the self-update Activity widget (version, check cadence, auto-install, apply progress)."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.ActivityWidgetComponents.self_update_widget/1

  def render_source, do: :function

  @now ~U[2026-06-07 16:00:00Z]
  @recent {:ok, ~U[2026-06-07 15:54:00Z]}

  defp base do
    %{
      version: "0.80.0",
      status: :up_to_date,
      latest_release: nil,
      last_check_at: @recent,
      now: @now,
      check_enabled?: true,
      interval_minutes: 15,
      auto_install?: true,
      apply_phase: nil,
      apply_progress: nil
    }
  end

  defp variant(overrides), do: Map.merge(base(), Map.new(overrides))

  def variations do
    [
      %Variation{
        id: :up_to_date,
        description: "On the latest release, auto-install on",
        attributes: variant(%{})
      },
      %Variation{
        id: :update_available,
        description: "A newer release exists, auto-install off",
        attributes:
          variant(
            status: :update_available,
            auto_install?: false,
            latest_release: %{
              tag: "v0.81.0",
              published_at: ~U[2026-06-07 09:00:00Z],
              html_url: "https://example.test/releases/v0.81.0",
              body: ""
            }
          )
      },
      %Variation{
        id: :checking,
        description: "A check is in flight",
        attributes: variant(status: :checking)
      },
      %Variation{
        id: :check_error,
        description: "The last check failed",
        attributes: variant(status: {:error, :not_found})
      },
      %Variation{
        id: :applying,
        description: "An update is downloading",
        attributes:
          variant(
            status: :update_available,
            latest_release: %{
              tag: "v0.81.0",
              published_at: ~U[2026-06-07 09:00:00Z],
              html_url: "https://example.test/releases/v0.81.0",
              body: ""
            },
            apply_phase: :downloading,
            apply_progress: 42
          )
      },
      %Variation{
        id: :apply_failed,
        description: "The last apply attempt failed",
        attributes:
          variant(
            status: :update_available,
            latest_release: %{
              tag: "v0.81.0",
              published_at: ~U[2026-06-07 09:00:00Z],
              html_url: "https://example.test/releases/v0.81.0",
              body: ""
            },
            apply_phase: :failed
          )
      },
      %Variation{
        id: :never_checked,
        description: "Never checked, automatic checks off",
        attributes:
          variant(
            status: :idle,
            last_check_at: :none,
            check_enabled?: false,
            auto_install?: false
          )
      }
    ]
  end
end
