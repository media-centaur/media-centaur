defmodule MediaCentaurWeb.Storybook.Status.PlaybackWidget do
  @moduledoc "Storybook coverage for the Playback Activity widget (active sessions + now-playing progress)."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.ActivityWidgetComponents.playback_widget/1

  def render_source, do: :function

  def variations do
    base_activity = %{
      recent: [
        %{title: "Sample Show — Pilot", kind: :episode, at: ~U[2026-06-09 12:00:00.000000Z]},
        %{title: "Movie A", kind: :movie, at: ~U[2026-06-08 20:00:00.000000Z]}
      ],
      last_write_at: ~U[2026-06-09 12:00:00.000000Z],
      lifetime: %{hours: 142, titles: 87, streak: 5}
    }

    empty_activity = %{recent: [], last_write_at: nil, lifetime: %{hours: 0, titles: 0, streak: 0}}

    playing_session = %{
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

    [
      %Variation{
        id: :idle_with_history,
        attributes: %{
          playback: %{state: :idle, now_playing: nil, sessions: %{}},
          playback_activity: base_activity
        }
      },
      %Variation{
        id: :idle_no_history,
        attributes: %{
          playback: %{state: :idle, now_playing: nil, sessions: %{}},
          playback_activity: empty_activity
        }
      },
      %Variation{
        id: :playing_connected,
        attributes: %{
          playback: %{state: :playing, now_playing: nil, sessions: playing_session},
          playback_activity: base_activity
        }
      },
      %Variation{
        id: :playing_connecting,
        attributes: %{
          playback: %{
            state: :starting,
            now_playing: nil,
            sessions: %{"entity-1" => %{playing_session["entity-1"] | state: :starting}}
          },
          playback_activity: base_activity
        }
      }
    ]
  end
end
