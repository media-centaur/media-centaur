defmodule MediaCentaurWeb.Storybook.Settings.SettingsRow do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_row/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :on,
        attributes: %{
          label: "Share what you watch",
          description: "Friends see a movie or an episode when you finish it.",
          checked: true,
          event: "toggle_share_watched"
        }
      },
      %Variation{
        id: :off,
        attributes: %{
          label: "Share your watchlist",
          description: "A title you list is shared with your friends; one you drop is withdrawn.",
          checked: false,
          event: "toggle_share_watchlist"
        }
      },
      %Variation{
        id: :disabled,
        description:
          "No click, `aria-disabled`, and the description says why — the row stays in " <>
            "the nav graph. The title view's Track release dates row while auto-grab is on.",
        attributes: %{
          id: "settings-row-disabled",
          label: "Track release dates",
          description: "Stays on while auto-grab is on.",
          checked: true,
          disabled?: true,
          event: "set_rung"
        }
      }
    ]
  end
end
