defmodule MediaCentaur.Playback.MpvSessionTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.{Events, MpvSession, WatchingTracker}

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

  describe "judge_completion/1" do
    defp watching_state(overrides) do
      struct!(
        MpvSession,
        Map.merge(
          %{
            entity_id: "movie-1",
            movie_id: "movie-1",
            duration: 6000.0,
            tracker: %{WatchingTracker.new() | saveable_position: 5500.0}
          },
          overrides
        )
      )
    end

    test "adds the playing movie once its saved position completes it" do
      {reason, state} = MpvSession.judge_completion(watching_state(%{}))

      assert reason =~ "reached 92.0%"
      assert MapSet.equal?(state.completed, MapSet.new([{:movie, "movie-1"}]))
    end

    test "judges the saved position, not a seek target ahead of it" do
      state =
        watching_state(%{
          position: 5900.0,
          tracker: %{WatchingTracker.new() | saveable_position: 3000.0}
        })

      assert {nil, %{completed: completed}} = MpvSession.judge_completion(state)
      assert MapSet.size(completed) == 0
    end

    test "keeps what an earlier file in the chain completed" do
      state =
        watching_state(%{
          movie_id: nil,
          episode_id: "episode-2",
          season_number: 1,
          episode_number: 2,
          completed: MapSet.new([{:episode, "episode-1", 1, 1}])
        })

      {_reason, state} = MpvSession.judge_completion(state)

      assert MapSet.equal?(
               state.completed,
               MapSet.new([{:episode, "episode-1", 1, 1}, {:episode, "episode-2", 1, 2}])
             )
    end

    test "names an episode by its id and its season and episode numbers" do
      {_reason, state} =
        MpvSession.judge_completion(
          watching_state(%{movie_id: nil, episode_id: "episode-7", season_number: 3, episode_number: 7})
        )

      assert MapSet.equal?(state.completed, MapSet.new([{:episode, "episode-7", 3, 7}]))
    end

    test "names an extra by its own id" do
      {_reason, state} =
        MpvSession.judge_completion(watching_state(%{movie_id: nil, extra_id: "extra-1"}))

      assert MapSet.equal?(state.completed, MapSet.new([{:extra, "extra-1"}]))
    end

    test "adds nothing for a file the session cannot attribute" do
      {_reason, state} = MpvSession.judge_completion(watching_state(%{movie_id: nil}))

      assert MapSet.size(state.completed) == 0
    end
  end

  describe "session_ended/1" do
    test "states the entity and everything the session completed" do
      state = struct!(MpvSession, %{entity_id: "movie-1", completed: MapSet.new([{:movie, "movie-1"}])})

      assert %Events.SessionEnded{entity_id: "movie-1", completed: completed} =
               MpvSession.session_ended(state)

      assert MapSet.equal?(completed, MapSet.new([{:movie, "movie-1"}]))
    end
  end
end
