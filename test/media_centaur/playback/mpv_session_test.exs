defmodule MediaCentaur.Playback.MpvSessionTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Playback.MpvSession

  describe "launch_target/2" do
    test "scopes the resume position to the first file via per-file option grouping" do
      assert MpvSession.launch_target("/media/a.mkv", 1200.5) ==
               ["--{", "--start=1200.5", "/media/a.mkv", "--}"]
    end

    test "no resume position yields the bare path with no start flag" do
      assert MpvSession.launch_target("/media/a.mkv", 0) == ["/media/a.mkv"]
    end

    # Regression pin for the ADR-062 leak: a bare global --start applies to
    # every playlist entry mpv loads, so an unwatched appended successor
    # would begin at the first episode's resume offset. The flag must only
    # ever appear inside a --{ … --} group.
    test "a resume position never produces a bare global --start" do
      flags = MpvSession.launch_target("/media/a.mkv", 300)
      start_index = Enum.find_index(flags, &String.starts_with?(&1, "--start="))
      assert Enum.at(flags, start_index - 1) == "--{"
      assert List.last(flags) == "--}"
    end
  end

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
