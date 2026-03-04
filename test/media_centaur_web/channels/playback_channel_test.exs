defmodule MediaCentaurWeb.PlaybackChannelTest do
  use MediaCentaurWeb.ChannelCase

  defp join_playback do
    {:ok, _reply, socket} =
      MediaCentaurWeb.UserSocket
      |> socket()
      |> subscribe_and_join(MediaCentaurWeb.PlaybackChannel, "playback")

    socket
  end

  describe "join" do
    test "reply has string-keyed state and now_playing fields" do
      {:ok, reply, _socket} =
        MediaCentaurWeb.UserSocket
        |> socket()
        |> subscribe_and_join(MediaCentaurWeb.PlaybackChannel, "playback")

      wire = json_roundtrip(reply)

      # The Manager is a shared singleton — its state depends on other tests.
      # Assert the wire format shape, not specific values.
      assert is_binary(wire["state"])
      assert Map.has_key?(wire, "now_playing")
    end
  end

  describe "playback pushes" do
    test "state_changed push with playing state includes full now_playing" do
      socket = join_playback()

      now_playing = %{
        entity_id: "550e8400-test-uuid",
        entity_name: "Severance",
        season_number: 2,
        episode_number: 3,
        episode_name: "Who Is Alive?",
        content_url: "/media/tv/Severance/S02/S02E03.mkv",
        position_seconds: 1200.5,
        duration_seconds: 3200.0
      }

      # Send directly to the channel process to avoid mutating the Manager singleton
      send(socket.channel_pid, {:playback_state_changed, :playing, now_playing})

      assert_push "playback:state_changed", payload
      wire = json_roundtrip(payload)

      assert wire["state"] == "playing"
      assert is_map(wire["now_playing"])
      assert wire["now_playing"]["entity_id"] == "550e8400-test-uuid"
      assert wire["now_playing"]["entity_name"] == "Severance"
      assert wire["now_playing"]["season_number"] == 2
      assert wire["now_playing"]["episode_number"] == 3
      assert wire["now_playing"]["episode_name"] == "Who Is Alive?"
      assert wire["now_playing"]["content_url"] == "/media/tv/Severance/S02/S02E03.mkv"
      assert wire["now_playing"]["position_seconds"] == 1200.5
      assert wire["now_playing"]["duration_seconds"] == 3200.0
    end

    test "state_changed push with paused state still includes now_playing" do
      socket = join_playback()

      now_playing = %{
        entity_id: "550e8400-test-uuid",
        entity_name: "Sample Movie",
        season_number: nil,
        episode_number: nil,
        episode_name: nil,
        content_url: "/media/movies/Sample Movie.mkv",
        position_seconds: 3600.0,
        duration_seconds: 9840.0
      }

      send(socket.channel_pid, {:playback_state_changed, :paused, now_playing})

      assert_push "playback:state_changed", payload
      wire = json_roundtrip(payload)

      assert wire["state"] == "paused"
      assert is_map(wire["now_playing"])
      assert wire["now_playing"]["entity_name"] == "Sample Movie"
      assert wire["now_playing"]["season_number"] == nil
      assert wire["now_playing"]["episode_name"] == nil
    end

    test "state_changed push with idle state has null now_playing" do
      socket = join_playback()

      send(socket.channel_pid, {:playback_state_changed, :stopped, nil})

      assert_push "playback:state_changed", payload
      wire = json_roundtrip(payload)

      assert wire["state"] == "stopped"
      assert wire["now_playing"] == nil
    end

    test "now_playing has all fields from API.md schema" do
      socket = join_playback()

      now_playing = %{
        entity_id: "test-uuid",
        entity_name: "Test Entity",
        season_number: 1,
        episode_number: 5,
        episode_name: "The Grim Barbarity of Optics and Design",
        content_url: "/media/tv/test/S01E05.mkv",
        position_seconds: 0.0,
        duration_seconds: 2800.0
      }

      send(socket.channel_pid, {:playback_state_changed, :playing, now_playing})

      assert_push "playback:state_changed", payload
      wire = json_roundtrip(payload)

      required_keys = [
        "entity_id",
        "entity_name",
        "season_number",
        "episode_number",
        "episode_name",
        "content_url",
        "position_seconds",
        "duration_seconds"
      ]

      for key <- required_keys do
        assert Map.has_key?(wire["now_playing"], key),
               "now_playing missing required key: #{key}"
      end
    end

    test "entity_progress_updated push includes progress, resumeTarget, and childTargets" do
      socket = join_playback()

      summary = %{
        current_episode: %{season: 2, episode: 3},
        episode_position_seconds: 1205.3,
        episode_duration_seconds: 3200.0,
        episodes_completed: 12,
        episodes_total: 20
      }

      resume_target = %{
        "action" => "resume",
        "targetId" => "ep-uuid",
        "name" => "Who Is Alive?",
        "seasonNumber" => 2,
        "episodeNumber" => 3,
        "positionSeconds" => 1205.3,
        "durationSeconds" => 3200.0
      }

      child_targets_delta = %{
        "ep-uuid" => %{
          "action" => "resume",
          "positionSeconds" => 1205.3,
          "durationSeconds" => 3200.0
        }
      }

      now = DateTime.utc_now()

      send(
        socket.channel_pid,
        {:entity_progress_updated, "660f9500-test-uuid", summary, resume_target,
         child_targets_delta, now}
      )

      assert_push "playback:entity_progress_updated", payload
      wire = json_roundtrip(payload)

      assert wire["entity_id"] == "660f9500-test-uuid"

      assert wire["progress"]["current_episode"] == %{"season" => 2, "episode" => 3}
      assert wire["progress"]["episode_position_seconds"] == 1205.3
      assert wire["progress"]["episode_duration_seconds"] == 3200.0
      assert wire["progress"]["episodes_completed"] == 12
      assert wire["progress"]["episodes_total"] == 20

      assert wire["resumeTarget"]["action"] == "resume"
      assert wire["resumeTarget"]["targetId"] == "ep-uuid"
      assert wire["resumeTarget"]["name"] == "Who Is Alive?"
      assert wire["resumeTarget"]["positionSeconds"] == 1205.3

      assert wire["childTargets"] == %{
               "ep-uuid" => %{
                 "action" => "resume",
                 "positionSeconds" => 1205.3,
                 "durationSeconds" => 3200.0
               }
             }

      assert wire["lastActivityAt"] == DateTime.to_iso8601(now)
    end

    test "entity_progress_updated push with null childTargets for standalone movies" do
      socket = join_playback()

      summary = %{
        current_episode: nil,
        episode_position_seconds: 3600.0,
        episode_duration_seconds: 9840.0,
        episodes_completed: 0,
        episodes_total: 1
      }

      resume_target = %{
        "action" => "resume",
        "name" => "Sample Movie",
        "positionSeconds" => 3600.0,
        "durationSeconds" => 9840.0
      }

      now = DateTime.utc_now()

      send(
        socket.channel_pid,
        {:entity_progress_updated, "550e8400-test-uuid", summary, resume_target, nil, now}
      )

      assert_push "playback:entity_progress_updated", payload
      wire = json_roundtrip(payload)

      assert wire["entity_id"] == "550e8400-test-uuid"
      assert wire["childTargets"] == nil
      assert wire["progress"]["current_episode"] == nil
      assert wire["progress"]["episodes_total"] == 1
      assert wire["lastActivityAt"] == DateTime.to_iso8601(now)
    end
  end
end
