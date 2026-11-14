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

  describe "decide/4" do
    defp decide(state),
      do: ProgressWriter.decide(state.completed, state.entry, state.properties, state.tracker)

    test "a persist short of the content end is a tick" do
      state = watching_state(%{tracker: %{WatchingTracker.new() | saveable_position: 3000.0}})

      assert {:tick, completed} = decide(state)
      assert MapSet.size(completed) == 0
    end

    test "persisting past the content end twice is one finish and no further write" do
      state = watching_state(%{})

      assert {{:finish, reason}, completed} = decide(state)
      assert reason =~ "reached estimated credits start"

      # The same viewing, a tick further into the credits.
      later = %{state | completed: completed, tracker: %{state.tracker | saveable_position: 5990.0}}

      assert {:nothing, ^completed} = decide(later)
    end

    test "a file the session cannot attribute is never written" do
      assert {:nothing, completed} = decide(watching_state(%{movie_id: nil}))
      assert MapSet.size(completed) == 0
    end

    test "a finish that failed is judged again at the next persist" do
      state = watching_state(%{})
      {{:finish, _reason}, completed} = decide(state)

      retried = %{state | completed: ProgressWriter.unfinished(completed, Entry.item(state.entry))}

      assert {{:finish, _reason}, _completed} = decide(retried)
    end
  end

  describe "completed?/2" do
    test "is true once the session's set holds the entry's item" do
      episode = entry(%{episode_id: "episode-1", season_number: 1, episode_number: 1})

      refute ProgressWriter.completed?(MapSet.new(), episode)
      assert ProgressWriter.completed?(MapSet.new([Entry.item(episode)]), episode)
    end

    test "is false for an unattributed entry" do
      refute ProgressWriter.completed?(MapSet.new(), entry(%{}))
    end
  end
end
