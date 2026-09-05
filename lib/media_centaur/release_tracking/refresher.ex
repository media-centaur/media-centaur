defmodule MediaCentaur.ReleaseTracking.Refresher do
  @moduledoc """
  The two release-tracking timers: the TMDB refresh cycle for every
  watched item (`refresh_all/0`, every `release_tracking_refresh_interval_hours`)
  and the want-ledger sweep (`sweep_now/0`, every
  `release_tracking_sweep_interval_minutes`). Reacting to library
  changes is `ReleaseTracking.LibraryListener`'s job.
  """
  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.{Differ, Helpers, RefreshSchedule}
  alias MediaCentaur.Settings
  alias MediaCentaur.TMDB.Client

  @last_swept_at_key "release_tracking:last_swept_at"
  @first_tick_floor_ms to_timeout(second: 10)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def refresh_all do
    GenServer.cast(__MODULE__, :refresh_all)
  end

  @doc "Refresh a single item. Can be called directly in tests."
  def refresh_item(%ReleaseTracking.Item{} = item) do
    case fetch_for_item(item) do
      {:ok, ^item, response, new_releases} ->
        commit_refresh(item, response, new_releases)

      {:error, ^item, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Run the cheap sweep synchronously: sync the want ledger per watched
  item and broadcast
  `{:tracking_sweep_completed}` (the drop planner's clock, ADR-056).
  Persists `last_swept_at`. Safe to call without the GenServer
  running — used by the timer, by tests, and by ops.
  """
  def sweep_now do
    do_sweep()
  end

  @impl true
  def init(_opts) do
    # A floor on the first tick: a Refresher restarted by its supervisor
    # after a crash must not tick straight into the same transient and
    # burn the restart budget (see `RefreshSchedule`).
    floor = [floor_ms: @first_tick_floor_ms]

    schedule_sweep(
      RefreshSchedule.next_delay_ms(last_swept_at(), sweep_interval_ms(), DateTime.utc_now(), floor)
    )

    schedule_refresh(
      RefreshSchedule.next_delay_ms(
        last_refresh_completed_at(),
        refresh_interval_ms(),
        DateTime.utc_now(),
        floor
      )
    )

    {:ok, %{}}
  end

  @impl true
  def handle_info(:refresh, state) do
    do_refresh_all()
    schedule_refresh(refresh_interval_ms())
    {:noreply, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    do_sweep()
    schedule_sweep(sweep_interval_ms())
    {:noreply, state}
  end

  @impl true
  def handle_cast(:refresh_all, state) do
    do_refresh_all()
    {:noreply, state}
  end

  defp do_refresh_all do
    Log.info(:acquisition, "release tracking: starting refresh cycle")

    items = ReleaseTracking.list_watching_items()

    # Phase 1: parallel TMDB fetches (network I/O). Safe to parallelize
    # because nothing writes to the DB yet.
    fetched =
      MediaCentaur.TaskSupervisor
      |> Task.Supervisor.async_stream_nolink(items, &fetch_for_item/1,
        max_concurrency: 4,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    # Phase 2: serialized commits. SQLite is a single-writer database; a
    # single commit loop avoids lock contention and the rollback that
    # comes with four concurrent write transactions.
    successful =
      Enum.flat_map(fetched, fn
        {:ok, {:ok, item, response, new_releases}} ->
          commit_refresh(item, response, new_releases)
          [{item, response}]

        {:ok, {:error, item, reason}} ->
          Log.info(:acquisition, "refresh failed for #{item.name}: #{inspect(reason)}")
          []

        {:exit, reason} ->
          Log.info(:acquisition, "refresh task crashed: #{inspect(reason)}")
          []
      end)

    # Phase 3: bounded parallel image backfill. Previously each commit
    # spawned its own Task.Supervisor.start_child, so N refreshed items
    # produced up to N concurrent image-download tasks competing for
    # bandwidth. Bound the fan-out the same way Phase 1 bounds TMDB
    # fetches.
    bulk_download_images(successful)

    changed_ids = Enum.map(items, & &1.id)

    if changed_ids != [] do
      MediaCentaur.Topics.publish(
        MediaCentaur.Topics.release_tracking_updates(),
        {:releases_updated, changed_ids}
      )
    end

    Log.info(:acquisition, "release tracking: refresh complete (#{length(items)} items)")
  end

  defp bulk_download_images([]), do: :ok

  defp bulk_download_images(items_with_responses) do
    MediaCentaur.TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(
      items_with_responses,
      fn {item, response} -> Helpers.download_images_sync(item, item.tmdb_id, response) end,
      max_concurrency: 4,
      timeout: 60_000,
      on_timeout: :kill_task
    )
    |> Stream.run()
  end

  # `reload: true` on every scheduled fetch: TMDB marks details fresh for
  # about eight hours, longer than the refresh interval, and this sweep
  # exists to notice what changed since last time.
  defp fetch_for_item(%{media_type: :tv_series} = item) do
    case Client.get_tv(item.tmdb_id, reload: true) do
      {:ok, response} ->
        new_releases =
          Helpers.fetch_tv_releases(
            item.tmdb_id,
            item.last_library_season,
            item.last_library_episode,
            response
          )

        {:ok, item, response, new_releases}

      {:error, reason} ->
        {:error, item, reason}
    end
  end

  # A `:movie` item is one of two TMDB resources, and the library link
  # says which: an item linked to a `MovieSeries` tracks a collection
  # (its `tmdb_id` is a collection id, written by the Scanner); any other
  # movie item tracks one film (a manual track from search).
  defp fetch_for_item(%{media_type: :movie, library_container_type: :movie_series} = item) do
    case Client.get_collection(item.tmdb_id, reload: true) do
      {:ok, response} -> {:ok, item, response, Helpers.fetch_collection_releases(response)}
      {:error, reason} -> {:error, item, reason}
    end
  end

  defp fetch_for_item(%{media_type: :movie} = item) do
    case Client.get_movie(item.tmdb_id, reload: true) do
      {:ok, response} -> {:ok, item, response, Helpers.fetch_movie_releases(response)}
      {:error, reason} -> {:error, item, reason}
    end
  end

  defp commit_refresh(item, response, new_releases) do
    old_releases = ReleaseTracking.list_releases_for_item(item.id)
    events = Differ.diff(old_releases, new_releases, item.media_type)
    write_events(item, events)
    replace_releases(item, new_releases)
    update_item_metadata(item, response)
    :ok
  end

  defp write_events(item, events) do
    Enum.each(events, fn event ->
      ReleaseTracking.create_event!(%{
        item_id: item.id,
        item_name: item.name,
        event_type: event.event_type,
        description: event.description,
        metadata: event.metadata
      })
    end)
  end

  defp replace_releases(item, new_releases) do
    ReleaseTracking.replace_releases!(item, new_releases, &ReleaseTracking.persist_release!/2)

    ReleaseTracking.mark_in_library_releases(item)
    ReleaseTracking.sync_wants(item)
  end

  defp update_item_metadata(item, response) do
    name = response["name"] || response["title"] || item.name

    ReleaseTracking.update_item(item, %{
      name: name,
      last_refreshed_at: DateTime.utc_now(),
      # Self-heals items created before the column existed; collection
      # responses carry no origin_country and keep the stored value.
      origin_country: response["origin_country"] || item.origin_country
    })
  end

  defp schedule_refresh(interval) do
    Process.send_after(self(), :refresh, interval)
  end

  defp schedule_sweep(interval) do
    Process.send_after(self(), :sweep, interval)
  end

  defp refresh_interval_ms do
    hours = MediaCentaur.Settings.Config.get(:release_tracking_refresh_interval_hours) || 6
    hours * 60 * 60 * 1000
  end

  defp sweep_interval_ms do
    minutes = MediaCentaur.Settings.Config.get(:release_tracking_sweep_interval_minutes) || 15
    minutes * 60 * 1000
  end

  defp do_sweep do
    Log.info(:acquisition, "release tracking: sweep")

    Enum.each(ReleaseTracking.list_watching_items(), fn item ->
      # The sweep is the want ledger's heartbeat (ADR-056): idempotent
      # sync per tick means the ledger self-backfills on first deploy
      # and self-heals after any missed seam.
      ReleaseTracking.sync_wants(item)
    end)

    # The drop planner's clock (ADR-056 Q2): the Reactor runs a tick
    # after every completed sweep, once the ledger sync is in.
    MediaCentaur.Topics.publish(
      MediaCentaur.Topics.release_tracking_updates(),
      {:tracking_sweep_completed}
    )

    persist_last_swept_at()
    :ok
  end

  defp last_swept_at do
    case Settings.get_by_key(@last_swept_at_key) do
      %{value: %{"timestamp" => iso}} when is_binary(iso) ->
        case DateTime.from_iso8601(iso) do
          {:ok, dt, _offset} -> dt
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp last_refresh_completed_at do
    case MediaCentaur.Repo.aggregate(ReleaseTracking.Item, :max, :last_refreshed_at) do
      %DateTime{} = dt -> dt
      _ -> nil
    end
  end

  defp persist_last_swept_at do
    attrs = %{
      key: @last_swept_at_key,
      value: %{"timestamp" => DateTime.to_iso8601(DateTime.utc_now())}
    }

    case Settings.find_or_create_entry(attrs) do
      {:ok, _entry} ->
        :ok

      {:error, changeset} ->
        Log.warning(
          :acquisition,
          "release tracking: failed to persist last_swept_at — #{inspect(changeset.errors)}"
        )

        :ok
    end
  end
end
