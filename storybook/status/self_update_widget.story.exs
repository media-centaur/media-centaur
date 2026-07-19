defmodule MediaCentaurWeb.Storybook.Status.SelfUpdateWidget do
  @moduledoc "Storybook coverage for the self-update Activity widget (version, check cadence, auto-install, apply progress)."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.StatusWidgets.SelfUpdate.self_update_widget/1

  def render_source, do: :function

  @now ~U[2026-06-09 12:00:00Z]
  @recent {:ok, ~U[2026-06-09 11:55:00Z]}

  @history [
    %{
      version: "0.86.1",
      recorded_at: ~U[2026-06-09 09:00:00Z],
      notes_body:
        "### Fixed\n\n**The Watcher tile no longer blanks the Status page.** It degrades gracefully during a restart."
    },
    %{version: "0.86.0", recorded_at: ~U[2026-06-08 09:00:00Z], notes_body: nil}
  ]

  defp base do
    %{
      version: "0.86.1",
      status: :up_to_date,
      latest_release: nil,
      last_check_at: @recent,
      now: @now,
      check_enabled?: true,
      interval_minutes: 360,
      auto_install?: false,
      apply_phase: nil,
      apply_progress: nil,
      history: @history
    }
  end

  defp variant(overrides), do: Map.merge(base(), Map.new(overrides))

  def variations do
    [
      %Variation{
        id: :up_to_date,
        description: "On the latest release — history has one entry with notes and one plain row",
        attributes: variant(%{})
      },
      %Variation{
        id: :update_available,
        description: "A newer release exists with what's-new notes",
        attributes:
          variant(
            status: :update_available,
            auto_install?: false,
            latest_release: %{
              version: "0.87.0",
              tag: "v0.87.0",
              published_at: @now,
              html_url: "https://example.com",
              body:
                "### Improved\n\n**The Updates tile now shows what each release brings.** Expand any version to read its notes."
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
              version: "0.87.0",
              tag: "v0.87.0",
              published_at: @now,
              html_url: "https://example.com",
              body: "### Improved\n\n**The Updates tile now shows what each release brings.**"
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
              version: "0.87.0",
              tag: "v0.87.0",
              published_at: @now,
              html_url: "https://example.com",
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
            auto_install?: false,
            history: []
          )
      }
    ]
  end
end
