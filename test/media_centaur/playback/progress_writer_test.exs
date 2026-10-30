defmodule MediaCentaur.Playback.ProgressWriterTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.{Entry, MpvProperties, ProgressWriter, WatchingTracker}

  defp entry(fields), do: struct!(%Entry{entity_id: "entity", content_url: "/media/a.mkv"}, fields)

  describe "judge/4" do
    # The judge's inputs as a session holds them, so each case reads as the
    # session's state: the entry's identity, the mirror, the tracker, the set.
    defp watching_state(overrides) do
      {entry_fields, overrides} =
        Map.split(overrides, ~w(movie_id episode_id extra_id season_number episode_number)a)

      Map.merge(
        %{
          entry: entry(Map.merge(%{entity_id: "movie-1", movie_id: "movie-1"}, entry_fields)),
          properties: %MpvProperties{duration: 6000.0},
          tracker: %{WatchingTracker.new() | saveable_position: 5850.0},
          completed: MapSet.new()
        },
        overrides
      )
    end

    defp judge(state),
      do: ProgressWriter.judge(state.completed, state.entry, state.properties, state.tracker)

    test "adds the playing movie once its saved position completes it" do
      {reason, completed} = judge(watching_state(%{}))

      assert reason =~ "reached estimated credits start"
      assert MapSet.equal?(completed, MapSet.new([{:movie, "movie-1"}]))
    end

    test "allows a movie longer credits than an episode" do
      # 400 s from the end: inside a movie's 8-minute credits, outside an
      # episode's 3 minutes.
      tracker = %{WatchingTracker.new() | saveable_position: 5600.0}

      assert {reason, _completed} = judge(watching_state(%{tracker: tracker}))
      assert reason

      assert {nil, _completed} =
               judge(watching_state(%{tracker: tracker, movie_id: nil, episode_id: "episode-1"}))
    end

    test "judges the saved position, not a seek target ahead of it" do
      state =
        watching_state(%{
          properties: %MpvProperties{duration: 6000.0, position: 5900.0},
          tracker: %{WatchingTracker.new() | saveable_position: 3000.0}
        })

      assert {nil, completed} = judge(state)
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

      {_reason, completed} = judge(state)

      assert MapSet.equal?(
               completed,
               MapSet.new([{:episode, "episode-1", 1, 1}, {:episode, "episode-2", 1, 2}])
             )
    end

    test "names an episode by its id and its season and episode numbers" do
      {_reason, completed} =
        judge(
          watching_state(%{movie_id: nil, episode_id: "episode-7", season_number: 3, episode_number: 7})
        )

      assert MapSet.equal?(completed, MapSet.new([{:episode, "episode-7", 3, 7}]))
    end

    test "names an extra by its own id" do
      {_reason, completed} =
        judge(watching_state(%{movie_id: nil, extra_id: "extra-1"}))

      assert MapSet.equal?(completed, MapSet.new([{:extra, "extra-1"}]))
    end

    test "adds nothing for a file the session cannot attribute" do
      {_reason, completed} = judge(watching_state(%{movie_id: nil}))

      assert MapSet.size(completed) == 0
    end
  end
end
