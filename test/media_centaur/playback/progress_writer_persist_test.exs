defmodule MediaCentaur.Playback.ProgressWriterPersistTest do
  @moduledoc """
  `ProgressWriter.persist/6` against the real Library: what a session's
  tick and finish leave behind, and what a failed finish reports.

  That a tick is never applied after the finish it preceded is not pinned
  here: it follows from the tick being the caller's own write, and a
  test cannot tell that from a task that happens to run first.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits
  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.ExtraProgress
  alias MediaCentaur.Library.Progress
  alias MediaCentaur.Library.ProgressRecords
  alias MediaCentaur.Library.WatchProgress
  alias MediaCentaur.Playback.{Entry, MpvProperties, ProgressWriter, WatchingTracker}
  alias MediaCentaur.Repo
  alias MediaCentaur.Topics

  setup do
    {:ok, _pid} = start_supervised({Progress.Worker, [flush_interval_ms: 60_000, name: Progress.Worker]})
    %{profile_id: owner_profile_id()}
  end

  defp movie_entry do
    movie = create_standalone_movie(%{name: "Movie A"})
    %Entry{entity_id: movie.id, movie_id: movie.id, content_url: "/media/movie-a.mkv"}
  end

  defp extra_entry do
    movie = create_standalone_movie(%{name: "Movie A"})
    extra = create_extra(%{name: "Featurette", movie_id: movie.id, content_url: "/media/featurette.mkv"})
    %Entry{entity_id: movie.id, extra_id: extra.id, content_url: "/media/featurette.mkv"}
  end

  defp persist(action, profile_id, entry, position, playable_item_id \\ nil) do
    ProgressWriter.persist(
      action,
      profile_id,
      entry,
      playable_item_id,
      %MpvProperties{duration: 6000.0},
      %{WatchingTracker.new() | saveable_position: position}
    )
  end

  describe "a playable item" do
    test "a tick is readable from memory as soon as persist returns", %{profile_id: profile_id} do
      entry = movie_entry()

      playable_item_id = persist(:tick, profile_id, entry, 300.0)

      # Read from memory alone, straight after the call.
      assert %{position_seconds: 300.0, duration_seconds: 6000.0} =
               Progress.overlay_in_memory(%WatchProgress{
                 profile_id: profile_id,
                 playable_item_id: playable_item_id
               })

      await_supervised_tasks()
    end

    test "the item resolved at the first persist is the one the next persist writes", %{
      profile_id: profile_id
    } do
      entry = movie_entry()

      playable_item_id = persist(:tick, profile_id, entry, 300.0)
      assert ^playable_item_id = persist(:tick, profile_id, entry, 310.0, playable_item_id)

      assert %WatchProgress{position_seconds: 310.0} = Progress.get(profile_id, playable_item_id)
      await_supervised_tasks()
    end

    test "a finish after ticks leaves the item marked with no viewing", %{profile_id: profile_id} do
      Topics.subscribe(Topics.library_watch_completed())
      entry = movie_entry()

      playable_item_id = persist(:tick, profile_id, entry, 300.0)
      persist({:finish, "reached estimated credits start"}, profile_id, entry, 5900.0, playable_item_id)
      await_supervised_tasks()

      assert_receive {:entity_watch_completed, %WatchProgress{playable_item_id: ^playable_item_id},
                      _actor}

      assert %WatchProgress{completed: true, position_seconds: +0.0} =
               Progress.get(profile_id, playable_item_id)

      refute_receive {:finish_failed, _item}
    end

    test "a finish that fails tells the session which item was not finished", %{profile_id: profile_id} do
      # An episode with no number cannot be given an order key: the tick
      # works, the finish does not.
      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 1})
      playable_item = create_playable_item_for_episode(episode)
      force_attrs(episode, episode_number: nil)

      entry = %Entry{
        entity_id: series.id,
        episode_id: episode.id,
        season_number: 1,
        episode_number: 1,
        content_url: "/media/sample-show-s01e01.mkv"
      }

      persist({:finish, "reached estimated credits start"}, profile_id, entry, 1250.0, playable_item.id)
      await_supervised_tasks()

      episode_id = episode.id
      assert_receive {:finish_failed, {:episode, ^episode_id, 1, 1}}
      refute Progress.get(profile_id, playable_item.id).completed
    end

    test "nothing to do writes nothing", %{profile_id: profile_id} do
      entry = movie_entry()

      assert nil == persist(:nothing, profile_id, entry, 300.0)
      assert [] == Repo.all(WatchProgress)
    end
  end

  describe "an extra" do
    test "a tick is persisted as soon as persist returns", %{profile_id: profile_id} do
      entry = extra_entry()

      persist(:tick, profile_id, entry, 40.0)

      assert {:ok, %ExtraProgress{position_seconds: 40.0, completed: false}} =
               ProgressRecords.fetch_for_extra(profile_id, entry.extra_id)

      await_supervised_tasks()
    end

    test "a finish after ticks leaves the extra marked with no viewing", %{profile_id: profile_id} do
      entry = extra_entry()

      persist(:tick, profile_id, entry, 40.0)
      persist({:finish, "reached end"}, profile_id, entry, 5990.0)
      await_supervised_tasks()

      assert {:ok, %ExtraProgress{completed: true, position_seconds: +0.0}} =
               ProgressRecords.fetch_for_extra(profile_id, entry.extra_id)

      refute_receive {:finish_failed, _item}
    end
  end
end
