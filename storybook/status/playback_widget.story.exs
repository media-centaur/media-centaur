defmodule MediaCentaurWeb.Storybook.Status.PlaybackWidget do
  @moduledoc "Storybook coverage for the Playback Activity widget: one row per player, its connection and what it plays."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.StatusWidgets.Playback.playback_widget/1

  def render_source, do: :function

  def variations do
    poster_data_uri =
      "data:image/svg+xml," <>
        URI.encode("""
        <svg xmlns="http://www.w3.org/2000/svg" width="40" height="60">\
        <rect width="40" height="60" fill="#2a2f45"/>\
        <rect y="30" width="40" height="30" fill="#1d2133"/></svg>\
        """)

    base_activity = %{
      recent: [
        %{
          title: "Sample Show S01E03 — The One With the Plan",
          kind: :episode,
          at: ~U[2026-06-09 12:00:00.000000Z],
          primary: "Sample Show",
          secondary: "S01E03 — The One With the Plan",
          poster_url: poster_data_uri
        },
        %{
          title: "Movie A",
          kind: :movie,
          at: ~U[2026-06-08 20:00:00.000000Z],
          primary: "Movie A",
          secondary: "Movie",
          poster_url: nil
        }
      ],
      last_write_at: ~U[2026-06-09 12:00:00.000000Z],
      lifetime: %{hours: 142, titles: 87, streak: 5}
    }

    empty_activity = %{recent: [], last_write_at: nil, lifetime: %{hours: 0, titles: 0, streak: 0}}

    episode = %{
      entity_id: "entity-1",
      entity_name: "Sample Show",
      episode_name: "Pilot",
      season_number: 1,
      episode_number: 1,
      position_seconds: 600,
      duration_seconds: 1800
    }

    movie = %{
      entity_id: "entity-2",
      movie_name: "Movie A",
      position_seconds: 3000,
      duration_seconds: 6000
    }

    viewing = fn state, now_playing, waiting? ->
      %{
        key: "viewing-#{now_playing.entity_id}",
        state: state,
        now_playing: now_playing,
        started_at: 1,
        profile_name: "Sample Profile",
        waiting?: waiting?
      }
    end

    host = %{
      id: "host",
      name: "This computer",
      icon: "hero-computer-desktop",
      device_line: nil,
      connection: :host,
      seen_line: nil,
      viewings: []
    }

    tv = %{
      id: "tv-1",
      name: "Living room TV",
      icon: "hero-tv",
      device_line: "Sample TV 4K · Android 12 · App 0.3.0 · WebView 131",
      connection: :connected,
      seen_line: nil,
      viewings: []
    }

    phone = %{
      id: "phone-1",
      name: "Phone",
      icon: "hero-device-phone-mobile",
      device_line: "Sample Phone · Android 14 · App 0.3.0 · WebView 131",
      connection: :offline,
      seen_line: "Last seen 3d ago from 192.168.1.52",
      viewings: []
    }

    [
      %Variation{
        id: :idle_with_history,
        description: "Every player idle: this computer, a connected TV, a phone last seen days ago.",
        attributes: %{player_rows: [host, tv, phone], playback_activity: base_activity}
      },
      %Variation{
        id: :idle_no_history,
        description: "A fresh install: this computer alone, nothing watched.",
        attributes: %{player_rows: [host], playback_activity: empty_activity}
      },
      %Variation{
        id: :two_players_playing,
        description: "The TV plays an episode, this computer a movie, paused.",
        attributes: %{
          player_rows: [
            %{host | viewings: [viewing.(:paused, movie, false)]},
            %{tv | viewings: [viewing.(:playing, episode, false)]},
            phone
          ],
          playback_activity: base_activity
        }
      },
      %Variation{
        id: :waiting_for_player,
        description: "The phone's channel dropped mid-viewing: the session waits for it to come back.",
        attributes: %{
          player_rows: [host, tv, %{phone | viewings: [viewing.(:playing, episode, true)]}],
          playback_activity: base_activity
        }
      },
      %Variation{
        id: :starting,
        description: "A viewing still starting on this computer.",
        attributes: %{
          player_rows: [%{host | viewings: [viewing.(:starting, movie, false)]}, tv],
          playback_activity: base_activity
        }
      }
    ]
  end
end
