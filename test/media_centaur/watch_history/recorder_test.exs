defmodule MediaCentaur.WatchHistory.RecorderTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.WatchHistory
  alias MediaCentaur.WatchHistory.Recorder

  setup do
    # Recorder is excluded from pubsub_listeners in test env — start it manually.
    # Allow it to access the sandbox DB connection owned by this test process.
    {:ok, pid} = Recorder.start_link([])
    Ecto.Adapters.SQL.Sandbox.allow(MediaCentaur.Repo, self(), pid)
    %{recorder: pid}
  end

  describe "handle_info :entity_progress_updated" do
    test "records a WatchEvent when a movie is completed", %{recorder: recorder} do
      movie = create_movie(%{name: "Sample Movie"})

      progress =
        create_watch_progress(%{
          movie_id: movie.id,
          completed: true,
          duration_seconds: 8880.0
        })

      WatchHistory.subscribe()

      send(
        recorder,
        {:entity_progress_updated,
         %{
           entity_id: movie.id,
           changed_record: progress,
           summary: nil,
           resume_target: nil,
           child_targets_delta: nil,
           last_activity_at: DateTime.utc_now()
         }}
      )

      assert_receive {:watch_event_created, event}, 2000
      assert event.title == "Sample Movie"
      assert event.entity_type == :movie
      assert event.movie_id == movie.id
      assert_in_delta event.duration_seconds, 8880.0, 0.01
    end

    test "records a WatchEvent when an episode is completed", %{recorder: recorder} do
      tv_series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 4})

      progress =
        create_watch_progress(%{
          episode_id: episode.id,
          completed: true,
          duration_seconds: 3600.0
        })

      WatchHistory.subscribe()

      send(
        recorder,
        {:entity_progress_updated,
         %{
           entity_id: tv_series.id,
           changed_record: progress,
           summary: nil,
           resume_target: nil,
           child_targets_delta: nil,
           last_activity_at: DateTime.utc_now()
         }}
      )

      assert_receive {:watch_event_created, event}, 2000
      assert event.title == "Sample Show S01E04"
      assert event.entity_type == :episode
      assert event.episode_id == episode.id
    end

    test "ignores progress updates where completed is false", %{recorder: recorder} do
      movie = create_movie(%{name: "Sample Movie Thirteen"})

      progress =
        create_watch_progress(%{movie_id: movie.id, completed: false, duration_seconds: 9000.0})

      WatchHistory.subscribe()

      send(
        recorder,
        {:entity_progress_updated,
         %{
           entity_id: movie.id,
           changed_record: progress,
           summary: nil,
           resume_target: nil,
           child_targets_delta: nil,
           last_activity_at: DateTime.utc_now()
         }}
      )

      refute_receive {:watch_event_created, _}, 500
      assert WatchHistory.list_events() == []
    end
  end
end
