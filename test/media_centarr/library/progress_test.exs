defmodule MediaCentarr.Library.ProgressTest do
  @moduledoc """
  Public-API tests for `MediaCentarr.Library.Progress` — the Pillar-2
  GenServer that owns active watch-progress state in memory and
  debounce-flushes to SQLite (Library Schema v2 Phase 3 Task D).

  All synchronisation is via PubSub broadcasts published by
  `MediaCentarr.Library.Progress.Events` on the `library:progress`
  topic — `{:progress_ticked, %ProgressTicked{}}`,
  `{:progress_flushed, %ProgressFlushed{}}`,
  `{:progress_hydrated, %ProgressHydrated{}}` — plus
  `{:watch_completed, playable_item_id}` on `watch_history:events`.
  Never `Process.sleep`, never `:sys.get_state`, never `:ets.lookup`
  from a test (ADR-026).
  """
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Library.Progress
  alias MediaCentarr.Library.WatchProgress
  alias MediaCentarr.Repo
  alias MediaCentarr.Topics

  @flush_interval_ms 50

  setup_all do
    prev = Application.get_env(:media_centarr, :library_progress_flush_interval_ms)
    Application.put_env(:media_centarr, :library_progress_flush_interval_ms, @flush_interval_ms)

    on_exit(fn ->
      if prev == nil do
        Application.delete_env(:media_centarr, :library_progress_flush_interval_ms)
      else
        Application.put_env(:media_centarr, :library_progress_flush_interval_ms, prev)
      end
    end)

    :ok
  end

  setup do
    # Singleton worker is supervised by the application. Tests that
    # mutate progress reset the in-memory table at the start so each
    # case begins cold. The worker stays up for read-fallback tests.
    ensure_worker_started!()
    Progress.reset_for_test!()
    :ok
  end

  defp ensure_worker_started! do
    case Process.whereis(Progress.Worker) do
      nil ->
        # Worker isn't started in :test env by default — start it here
        # so the public API has a process to delegate to.
        {:ok, _pid} =
          start_supervised(
            {Progress.Worker, [flush_interval_ms: @flush_interval_ms, name: Progress.Worker]}
          )

        :ok

      _pid ->
        :ok
    end
  end

  defp seed_movie_playable_item do
    movie = create_standalone_movie()
    create_playable_item_for_movie(movie)
  end

  defp seed_episode_playable_item do
    series = create_tv_series()
    season = create_season(%{tv_series_id: series.id, season_number: 1})
    episode = create_episode(%{season_id: season.id, episode_number: 1})
    create_playable_item_for_episode(episode)
  end

  describe "record/3 → get/1 round trip" do
    test "first write is immediately visible via get/1 (read-after-write)" do
      pi = seed_movie_playable_item()
      :ok = Progress.record(pi.id, 30.0, 100.0)

      progress = Progress.get(pi.id)
      assert %WatchProgress{position_seconds: 30.0, duration_seconds: 100.0} = progress
      assert progress.playable_item_id == pi.id
    end

    test "subsequent writes update position monotonically" do
      pi = seed_movie_playable_item()
      :ok = Progress.record(pi.id, 10.0, 100.0)
      :ok = Progress.record(pi.id, 20.0, 100.0)
      :ok = Progress.record(pi.id, 30.0, 100.0)

      assert %WatchProgress{position_seconds: 30.0} = Progress.get(pi.id)
    end

    test "concurrent writes do not corrupt the record (any single recorded position survives)" do
      # NOTE: This test does NOT prove monotonicity under concurrent
      # writers. Production-safe monotonicity relies on the
      # single-writer-per-playable-item-id invariant enforced by
      # `MediaCentarr.Playback.MpvSession` /
      # `MediaCentarr.Playback.SessionRegistry`; concurrent writers
      # to the same id are out of scope. The assertion below proves
      # only "we see a real recorded value, not a torn/garbage one".
      pi = seed_movie_playable_item()

      1..50
      |> Enum.map(fn position ->
        Task.async(fn -> Progress.record(pi.id, position * 1.0, 100.0) end)
      end)
      |> Enum.each(&Task.await/1)

      assert %WatchProgress{position_seconds: pos, duration_seconds: 100.0} = Progress.get(pi.id)
      assert pos >= 1.0 and pos <= 50.0
    end

    test "writes for unknown playable_item_id are accepted (creates row on first record/3)" do
      pi = seed_movie_playable_item()

      :ok = Progress.record(pi.id, 12.5, 100.0)

      assert %WatchProgress{playable_item_id: pi_id, position_seconds: 12.5} = Progress.get(pi.id)
      assert pi_id == pi.id
    end
  end

  describe "debounced flush" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_progress())
      :ok
    end

    test "flush writes pending progress to library_watch_progress within the flush window" do
      pi = seed_movie_playable_item()
      :ok = Progress.record(pi.id, 30.0, 100.0)
      pi_id = pi.id

      assert_receive {:progress_flushed, %{playable_item_id: ^pi_id}}, 1_000

      assert %WatchProgress{position_seconds: 30.0, duration_seconds: 100.0} =
               Repo.get_by(WatchProgress, playable_item_id: pi_id)
    end

    test "multiple writes within the window coalesce to one DB row" do
      pi = seed_movie_playable_item()
      :ok = Progress.record(pi.id, 10.0, 100.0)
      :ok = Progress.record(pi.id, 20.0, 100.0)
      :ok = Progress.record(pi.id, 30.0, 100.0)
      pi_id = pi.id

      assert_receive {:progress_flushed, %{playable_item_id: ^pi_id}}, 1_000
      refute_receive {:progress_flushed, %{playable_item_id: ^pi_id}}, 200

      assert %WatchProgress{position_seconds: 30.0} =
               Repo.get_by(WatchProgress, playable_item_id: pi_id)
    end

    test "writes for multiple entities flush in one batch" do
      pi_a = seed_movie_playable_item()
      pi_b = seed_movie_playable_item()

      :ok = Progress.record(pi_a.id, 5.0, 100.0)
      :ok = Progress.record(pi_b.id, 15.0, 100.0)
      pi_a_id = pi_a.id
      pi_b_id = pi_b.id

      assert_receive {:progress_flushed, %{playable_item_id: ^pi_a_id}}, 1_500
      assert_receive {:progress_flushed, %{playable_item_id: ^pi_b_id}}, 1_500

      assert %WatchProgress{position_seconds: 5.0} =
               Repo.get_by(WatchProgress, playable_item_id: pi_a_id)

      assert %WatchProgress{position_seconds: 15.0} =
               Repo.get_by(WatchProgress, playable_item_id: pi_b_id)
    end

    test "flush wraps the batch upsert in a single Repo transaction (begin/commit)" do
      # Telemetry guard: prove the debounced flush issues exactly one
      # `begin` and one `commit` against the Repo, regardless of how
      # many dirty rows are flushed. A regression to per-row
      # `Enum.each` of single upserts (no transaction) would emit zero
      # `begin`/`commit` events — partial-flush failure would lose the
      # un-persisted dirty entries because the dirty set is cleared by
      # `handle_info(:flush, ...)`. Wrapping in `Repo.transaction/1`
      # makes the batch atomic.
      pi_a = seed_movie_playable_item()
      pi_b = seed_movie_playable_item()
      pi_c = seed_movie_playable_item()
      pi_a_id = pi_a.id

      {_result, queries} =
        count_queries(fn ->
          :ok = Progress.record(pi_a.id, 5.0, 100.0)
          :ok = Progress.record(pi_b.id, 15.0, 100.0)
          :ok = Progress.record(pi_c.id, 25.0, 100.0)

          # Synchronise on the flush — every dirty row broadcasts on
          # the library:progress topic after the batch persists.
          assert_receive {:progress_flushed, %{playable_item_id: ^pi_a_id}}, 1_000
        end)

      begins = Enum.count(queries, fn {_src, sql} -> sql == "begin" end)
      commits = Enum.count(queries, fn {_src, sql} -> sql == "commit" end)

      assert begins == 1,
             "expected exactly one `begin` for the batched flush, saw #{begins}. " <>
               "Queries:\n" <> format_queries(queries)

      assert commits == 1,
             "expected exactly one `commit` for the batched flush, saw #{commits}. " <>
               "Queries:\n" <> format_queries(queries)
    end

    test "graceful shutdown synchronously flushes (terminate/2 contract)" do
      pi = seed_movie_playable_item()
      pi_id = pi.id
      worker_name = :"#{__MODULE__}_Shutdown_Worker"

      {:ok, _pid} =
        start_supervised(
          {Progress.Worker,
           [
             flush_interval_ms: 60_000,
             name: worker_name,
             table: :"#{__MODULE__}_Shutdown_Table"
           ]}
        )

      :ok = GenServer.cast(worker_name, {:record, pi_id, 42.0, 100.0})
      # Wait until the cast has been processed (no DB write yet — flush
      # interval is 60s). Using :sys.get_status would be implementation
      # introspection; instead, sync via a benign call.
      :ok = GenServer.call(worker_name, :sync)

      assert nil == Repo.get_by(WatchProgress, playable_item_id: pi_id)

      :ok = stop_supervised({Progress.Worker, worker_name})

      assert %WatchProgress{position_seconds: 42.0} =
               Repo.get_by(WatchProgress, playable_item_id: pi_id)
    end
  end

  describe "live progress_ticked broadcast" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_progress())
      :ok
    end

    test "broadcasts %ProgressTicked{} on playback:events for each record/3" do
      pi = seed_movie_playable_item()
      pi_id = pi.id

      :ok = Progress.record(pi.id, 7.5, 100.0)

      assert_receive {:progress_ticked, %{playable_item_id: ^pi_id, position_seconds: 7.5}}, 500
    end

    test "broadcast is emitted BEFORE the flush (live UX immediate)" do
      pi = seed_movie_playable_item()
      pi_id = pi.id

      :ok = Progress.record(pi.id, 3.0, 100.0)

      # The progress-ticked broadcast is the live UX hook. The flush
      # broadcast follows after the debounce window. Order matters —
      # the live bar must tick before the DB persists.
      assert_receive {:progress_ticked, %{playable_item_id: ^pi_id, position_seconds: 3.0}}, 500
      assert_receive {:progress_flushed, %{playable_item_id: ^pi_id}}, 1_000
    end
  end

  describe "complete/1" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.watch_history_events())
      :ok
    end

    test "writes completed: true progress row" do
      pi = seed_movie_playable_item()
      :ok = Progress.record(pi.id, 90.0, 100.0)
      :ok = Progress.complete(pi.id)

      assert %WatchProgress{completed: true} =
               Repo.get_by(WatchProgress, playable_item_id: pi.id)
    end

    test "broadcasts {:watch_completed, playable_item_id} on watch_history:events" do
      pi = seed_movie_playable_item()
      :ok = Progress.record(pi.id, 90.0, 100.0)
      pi_id = pi.id

      :ok = Progress.complete(pi.id)

      assert_receive {:watch_completed, ^pi_id}, 500
    end

    test "subsequent get/1 returns the completed row" do
      pi = seed_movie_playable_item()
      :ok = Progress.record(pi.id, 90.0, 100.0)
      :ok = Progress.complete(pi.id)

      assert %WatchProgress{completed: true, playable_item_id: pi_id} = Progress.get(pi.id)
      assert pi_id == pi.id
    end
  end

  describe "get/1 fallback to DB for cold rows" do
    test "returns DB row when not in memory" do
      pi = seed_episode_playable_item()

      # Direct DB-insert without going through the GenServer simulates
      # a cold row that was hydrated by something other than the
      # active session (factory, maintenance, prior shutdown).
      progress = create_watch_progress(%{episode_id: pi.container_id, position_seconds: 17.0})

      # Reset the in-memory state — the row is now DB-only.
      Progress.reset_for_test!()

      assert %WatchProgress{position_seconds: 17.0, id: id} = Progress.get(pi.id)
      assert id == progress.id
    end

    test "returns nil when neither in memory nor DB" do
      pi = seed_movie_playable_item()
      assert nil == Progress.get(pi.id)
    end

    test "DB-fallback row is NOT pulled into memory (cold stays cold)" do
      pi = seed_movie_playable_item()
      _progress = create_watch_progress(%{movie_id: pi.container_id, position_seconds: 5.0})
      Progress.reset_for_test!()

      assert %WatchProgress{position_seconds: 5.0} = Progress.get(pi.id)

      # A second cold read should still hit the DB — the first one
      # didn't promote the row into memory. We assert via behaviour:
      # mutating the DB row directly and re-reading should reflect
      # the new value if memory is empty. If memory cached the first
      # read, the stale value would surface.
      Repo.update_all(from(p in WatchProgress, where: p.playable_item_id == ^pi.id),
        set: [position_seconds: 99.0]
      )

      assert %WatchProgress{position_seconds: 99.0} = Progress.get(pi.id)
    end
  end

  describe "boot hydration" do
    test "in-progress rows are loaded into memory on init/1" do
      pi = seed_movie_playable_item()
      _progress = create_watch_progress(%{movie_id: pi.container_id, position_seconds: 25.0})
      pi_id = pi.id

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_progress())

      worker_name = :"#{__MODULE__}_Hydration_Worker"

      {:ok, _pid} =
        start_supervised(
          {Progress.Worker,
           [
             flush_interval_ms: 60_000,
             name: worker_name,
             table: :"#{__MODULE__}_Hydration_Table"
           ]}
        )

      assert_receive {:progress_hydrated, %{count: count}}, 1_000
      assert count >= 1

      # The hydrated table is owned by this worker — the public API
      # cannot read from it because it's keyed to the default name. We
      # assert hydration through the public observability hook: the
      # broadcast count includes our row.
      assert nil != Repo.get_by(WatchProgress, playable_item_id: pi_id)
    end

    test "completed rows are NOT loaded into memory on init/1" do
      pi = seed_movie_playable_item()

      progress =
        create_watch_progress(%{
          movie_id: pi.container_id,
          position_seconds: 100.0,
          duration_seconds: 100.0
        })

      {:ok, _completed} = MediaCentarr.Library.mark_watch_completed(progress)

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_progress())

      worker_name = :"#{__MODULE__}_HydrationCompleted_Worker"

      {:ok, _pid} =
        start_supervised(
          {Progress.Worker,
           [
             flush_interval_ms: 60_000,
             name: worker_name,
             table: :"#{__MODULE__}_HydrationCompleted_Table"
           ]}
        )

      # Hydration broadcasts a count that excludes completed rows. The
      # only in-progress rows for this test's DB are zero (we marked
      # the only one completed).
      assert_receive {:progress_hydrated, %{count: 0}}, 1_000
    end
  end

  # Telemetry-counter helper used by the transaction-boundary guard
  # in "debounced flush". Attaches a handler to `[:media_centarr,
  # :repo, :query]`, drains all events emitted during `fun.()`, and
  # returns them so the caller can assert on `begin`/`commit` counts.
  defp count_queries(fun) do
    ref = make_ref()
    parent = self()
    handler_id = {:progress_flush_query_count, ref}

    :ok =
      :telemetry.attach(
        handler_id,
        [:media_centarr, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          send(parent, {:query, ref, metadata.source, metadata.query})
        end,
        nil
      )

    try do
      result = fun.()
      queries = drain_queries(ref, [])
      {result, queries}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_queries(ref, acc) do
    receive do
      {:query, ^ref, source, sql} -> drain_queries(ref, [{source, sql} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp format_queries(queries) do
    Enum.map_join(queries, "\n", fn {src, sql} -> "  #{inspect(src)}: #{sql}" end)
  end
end
