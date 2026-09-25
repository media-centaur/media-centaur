defmodule MediaCentaur.Playback.MpvSessionTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.MpvSession

  describe "queue_next?/1" do
    defp queue_state(overrides) do
      struct!(
        MpvSession,
        Map.merge(
          %{episode_id: "ep-1", socket: :fake_socket, playlist_count: 1, playlist_pos: 0},
          overrides
        )
      )
    end

    test "queues while the current entry is the playlist's last" do
      assert MpvSession.queue_next?(queue_state(%{}))
    end

    test "does not queue when a successor is already pending" do
      refute MpvSession.queue_next?(queue_state(%{pending_next: %{episode_id: "ep-2"}}))
    end

    test "does not queue when the current entry is not the playlist tail" do
      refute MpvSession.queue_next?(queue_state(%{playlist_count: 3, playlist_pos: 1}))
    end

    test "does not queue while exiting or without a socket" do
      refute MpvSession.queue_next?(queue_state(%{exiting?: true}))
      refute MpvSession.queue_next?(queue_state(%{socket: nil}))
    end
  end
end
