defmodule MediaCentaurWeb.Storybook.Status.TmdbWidget do
  @moduledoc "Storybook coverage for the TMDB Activity widget (external-integration config + rate-limiter budget)."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.ActivityWidgetComponents.tmdb_widget/1

  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :not_configured,
        attributes: %{
          rate_limiter: nil,
          config: %{tmdb_configured: false}
        }
      },
      %Variation{
        id: :configured,
        attributes: %{
          rate_limiter: %{used: 12, total: 40},
          config: %{tmdb_configured: true}
        }
      }
    ]
  end
end
