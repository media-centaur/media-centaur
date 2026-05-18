defmodule MediaCentarr.Playback.ProgressBroadcasterTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Playback.ProgressBroadcaster

  describe "broadcast/2" do
    test "broadcasts entity_progress_updated for entity with progress" do
      tv_series = create_entity(%{type: :tv_series, name: "Broadcast Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/tv/show/s01e01.mkv"
        })

      create_watch_progress(%{
        episode_id: episode.id,
        position_seconds: 600.0,
        duration_seconds: 2400.0
      })

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.playback_events())

      ProgressBroadcaster.broadcast(tv_series.id)

      assert_receive {:entity_progress_updated,
                      %{
                        entity_id: entity_id,
                        summary: summary,
                        changed_record: changed_record
                      }}

      assert entity_id == tv_series.id
      assert is_map(summary)
      assert changed_record == nil
    end

    test "threads changed_record through the broadcast payload" do
      tv_series = create_entity(%{type: :tv_series, name: "Threaded Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/tv/show/s01e01.mkv"
        })

      record =
        create_watch_progress(%{
          episode_id: episode.id,
          position_seconds: 0.0,
          duration_seconds: 0.0
        })

      {:ok, record} = MediaCentarr.Library.mark_watch_completed(record)

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.playback_events())

      ProgressBroadcaster.broadcast(tv_series.id, record)

      assert_receive {:entity_progress_updated,
                      %{
                        entity_id: entity_id,
                        changed_record: changed_record
                      }}

      assert entity_id == tv_series.id
      assert changed_record.id == record.id

      # WatchProgress is keyed by `playable_item_id` since Library Schema
      # v2 Phase 2 Task C; the linked PlayableItem carries the
      # `(container_type, container_id)` discriminator. The broadcaster
      # substitutes a synthesised-`:playable_item` version (from
      # `EntityShape.extract_progress/2`) so subscribers can key by
      # container id without an extra preload.
      assert changed_record.playable_item.container_type == :episode
      assert changed_record.playable_item.container_id == episode.id
      assert changed_record.completed == true
    end

    test "returns :ok for nonexistent entity" do
      assert :ok == ProgressBroadcaster.broadcast(Ecto.UUID.generate())
    end

    test "changed_record in payload carries :playable_item container info" do
      # Regression: subscribers (EntityModal hook) rebuild per-episode
      # state from the broadcast payload's `changed_record` by reading
      # `record.playable_item.container_id` (via
      # `EpisodeList.progress_container_id/1`). The caller's raw record
      # — what `Library.fetch_watch_progress_by_fk/2` and
      # `mark_watch_completed!/1` return — has the `:playable_item`
      # association as `%Ecto.Association.NotLoaded{}`, so without
      # substitution the modal's in-memory merge dropped the record on
      # the floor and the episode silently flipped back to :unwatched.
      #
      # Reproduces the real toggle path:
      # `fetch_watch_progress_by_fk/2` returns an un-preloaded record →
      # `mark_watch_completed!/1` preserves the un-preloaded shape →
      # `ProgressBroadcaster.broadcast/2` must substitute a preloaded
      # version for the broadcast payload.
      tv_series = create_entity(%{type: :tv_series, name: "Toggle Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/tv/show/s01e01.mkv"
        })

      _seeded =
        create_watch_progress(%{
          episode_id: episode.id,
          position_seconds: 0.0,
          duration_seconds: 0.0
        })

      # Faithfully reproduce the runtime flow used by
      # `EntityModal.toggle_watch_progress/3`: fetch via the legacy FK
      # helper (no preload), then mark completed. The resulting record
      # has `playable_item: %Ecto.Association.NotLoaded{}`.
      {:ok, raw_progress} =
        MediaCentarr.Library.fetch_watch_progress_by_fk(:episode_id, episode.id)

      {:ok, raw_progress} = MediaCentarr.Library.mark_watch_completed(raw_progress)

      assert match?(%Ecto.Association.NotLoaded{}, raw_progress.playable_item)

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.playback_events())

      ProgressBroadcaster.broadcast(tv_series.id, raw_progress)

      assert_receive {:entity_progress_updated, %{changed_record: changed_record}}

      assert changed_record.id == raw_progress.id
      assert is_map(changed_record.playable_item)
      refute match?(%Ecto.Association.NotLoaded{}, changed_record.playable_item)
      assert changed_record.playable_item.container_type == :episode
      assert changed_record.playable_item.container_id == episode.id
    end
  end

  describe "stale-read window — broadcast must reflect in-memory progress" do
    # Regression for Library Schema v2 Phase 3 Task E I-2: the
    # `LibraryProgress.record/3` hot-path writes to the in-memory ETS
    # table only; the debounced flush persists to disk on the next
    # interval (default ~5s). Before Phase 3 Task E,
    # `ProgressBroadcaster.broadcast/1` re-read entity progress via
    # `TypeResolver.resolve_container` + Repo preload — which would
    # see the *stale* persisted row, not the fresh in-memory state.
    # The fix overlays `Library.Progress.get/1` for every record's
    # `playable_item_id` after the DB load.

    alias MediaCentarr.Library.Progress

    @flush_interval_ms 60_000

    defp ensure_progress_worker! do
      case Process.whereis(Progress.Worker) do
        nil ->
          {:ok, _pid} =
            start_supervised(
              {Progress.Worker, [flush_interval_ms: @flush_interval_ms, name: Progress.Worker]}
            )

          :ok

        _pid ->
          :ok
      end
    end

    test "broadcast payload reflects fresh in-memory position written via Progress.record/3" do
      ensure_progress_worker!()
      Progress.reset_for_test!()

      # Seed a movie with a *stale* persisted WatchProgress at 10s.
      movie = create_standalone_movie(%{name: "Stale Read Movie"})
      pi = create_playable_item_for_movie(movie)

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 10.0,
        duration_seconds: 100.0
      })

      # Write a *fresh* in-memory position via the Pillar-2 GenServer.
      # The flush interval is 60s, so the persisted row stays at 10s
      # for the duration of the test.
      :ok = Progress.record(pi.id, 75.0, 100.0)

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.playback_events())

      ProgressBroadcaster.broadcast(movie.id)

      assert_receive {:entity_progress_updated,
                      %{
                        entity_id: entity_id,
                        summary: summary
                      }}

      assert entity_id == movie.id

      # The summary's episode_position_seconds must reflect the fresh
      # in-memory 75s, not the persisted 10s. Before the fix this
      # carried 10.0 because the broadcaster re-read from the DB.
      assert summary.episode_position_seconds == 75.0
    end
  end
end
