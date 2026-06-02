defmodule MediaCentaurWeb.Storybook.Status.PlaybackWidget do
  @moduledoc "Storybook coverage for the Playback Activity widget (active sessions + now-playing progress)."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.ActivityWidgetComponents.playback_widget/1

  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :idle,
        attributes: %{
          playback: %{state: :idle, now_playing: nil, sessions: %{}}
        }
      },
      %Variation{
        id: :playing,
        attributes: %{
          playback: %{
            state: :playing,
            now_playing: nil,
            sessions: %{
              "entity-1" => %{
                state: :playing,
                started_at: 1,
                now_playing: %{
                  entity_id: "entity-1",
                  entity_name: "Sample Show",
                  episode_name: "Pilot",
                  season_number: 1,
                  episode_number: 1,
                  position_seconds: 600,
                  duration_seconds: 1800
                }
              }
            }
          }
        }
      }
    ]
  end
end
