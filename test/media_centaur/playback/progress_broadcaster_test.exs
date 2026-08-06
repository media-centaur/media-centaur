defmodule MediaCentaur.Playback.ProgressBroadcasterTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.Progress
  alias MediaCentaur.Library.ProgressRecords
  alias MediaCentaur.Playback.ProgressBroadcaster

  describe "broadcast/2" do
    # Reproduces the manual-completion-during-active-playback race: a user
    # finishes an episode at 89% (mpv never crosses its 90% auto-complete
    # bar, so its hot in-memory row stays completed:false) and clicks "mark
    # watched". The toggle writes the DB (completed:true) but never the hot
    # row. The broadcast overlay must surface the DB completion, not revert
    # it from the stale hot row — otherwise the modal badge never flips and
    # only a page reload shows the item as watched.
    test "a live in-memory tick never downgrades a manual DB completion" do
      # Worker isn't started in :test by default; 5s flush keeps the hot
      # row from persisting during the sub-millisecond broadcast.
      start_supervised!({Progress.Worker, [flush_interval_ms: 5_000, name: Progress.Worker]})
      Progress.reset_for_test!()

      tv_series = create_entity(%{type: :tv_series, name: "Overlay Race Show"})
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
          position_seconds: 1659.0,
          duration_seconds: 1851.0
        })

      # mpv mid-playback hot row at ~89% — completed:false
      :ok = Progress.record(record.playable_item_id, 1659.0, 1851.0)

      # Manual "mark watched": writes DB completed:true, leaves the hot row.
      {:ok, _completed} = ProgressRecords.mark_completed(record)

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.playback_events())
      ProgressBroadcaster.broadcast(tv_series.id, record)

      assert_receive {:entity_progress_updated, %{changed_record: changed_record}}
      assert changed_record.completed == true
    end

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

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.playback_events())

      ProgressBroadcaster.broadcast(tv_series.id, nil)

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

      {:ok, record} = ProgressRecords.mark_completed(record)

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.playback_events())

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
      assert :ok == ProgressBroadcaster.broadcast(Ecto.UUID.generate(), nil)
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
        ProgressRecords.fetch_for_container(:episode, episode.id)

      {:ok, raw_progress} = ProgressRecords.mark_completed(raw_progress)

      assert match?(%Ecto.Association.NotLoaded{}, raw_progress.playable_item)

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.playback_events())

      ProgressBroadcaster.broadcast(tv_series.id, raw_progress)

      assert_receive {:entity_progress_updated, %{changed_record: changed_record}}

      assert changed_record.id == raw_progress.id
      assert is_map(changed_record.playable_item)
      refute match?(%Ecto.Association.NotLoaded{}, changed_record.playable_item)
      assert changed_record.playable_item.container_type == :episode
      assert changed_record.playable_item.container_id == episode.id
    end

    test "accepts a playable_item_id (the MpvSession playback path) and threads the record" do
      # Regression: the playback path (`MediaCentaur.Playback.MpvSession`)
      # knows the *playable item* that ticked, not a `%WatchProgress{}`
      # struct, so it called `broadcast/1` with no changed record. The
      # payload arrived with `changed_record: nil`, the detail modal's
      # in-memory merge no-op'd (`merge_progress_record(records, nil)`),
      # and the per-episode watched badge never flipped live — only a
      # full remount showed the new state. The broadcaster must accept a
      # `playable_item_id` and resolve it to the freshly-loaded record
      # (with synthesised `:playable_item`) the same way the struct form
      # does.
      tv_series = create_entity(%{type: :tv_series, name: "Playback Show"})
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
          position_seconds: 600.0,
          duration_seconds: 2400.0
        })

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.playback_events())

      ProgressBroadcaster.broadcast(tv_series.id, record.playable_item_id)

      assert_receive {:entity_progress_updated, %{changed_record: changed_record}}

      assert changed_record
      assert changed_record.playable_item_id == record.playable_item_id
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

    alias MediaCentaur.Library.Progress

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
      playable_item = create_playable_item_for_movie(movie)

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 10.0,
        duration_seconds: 100.0
      })

      # Write a *fresh* in-memory position via the Pillar-2 GenServer.
      # The flush interval is 60s, so the persisted row stays at 10s
      # for the duration of the test.
      :ok = Progress.record(playable_item.id, 75.0, 100.0)

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.playback_events())

      ProgressBroadcaster.broadcast(movie.id, nil)

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
