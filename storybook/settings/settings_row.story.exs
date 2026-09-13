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
      }
    ]
  end
end
