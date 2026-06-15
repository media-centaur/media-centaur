defmodule MediaCentaur.ReleaseTracking.Refresher do
  @moduledoc """
  GenServer that periodically refreshes TMDB data for all tracked items.
  """
  use GenServer

  import Ecto.Query
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.{Differ, Helpers, RefreshSchedule}
  alias MediaCentaur.Settings
  alias MediaCentaur.TMDB.Client

  @last_swept_at_key "release_tracking:last_swept_at"

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
  Run the cheap sweep synchronously: mark past releases as released,
  sync the want ledger per watched item, and broadcast
  `{:tracking_sweep_completed}` (the drop planner's clock, ADR-056).
  Persists `last_swept_at`. Safe to call without the GenServer
  running — used by the timer, by tests, and by ops.
  """
  def sweep_now do
    do_sweep()
  end

  @doc "Update tracking items when library entities change. Testable without GenServer."
  def refresh_item_tracking_for(entity_ids) do
    update_last_episodes_for(entity_ids)
  end

  @doc "Auto-track new library entities with active TMDB status. Testable without GenServer."
  def auto_track_new_entities(entity_ids) do
    Enum.each(find_trackable_tv_series(entity_ids), &auto_track_tv_series/1)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_updates())
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_deletions())
    schedule_sweep(RefreshSchedule.next_delay_ms(last_swept_at(), sweep_interval_ms()))
    schedule_refresh(RefreshSchedule.next_delay_ms(last_refresh_completed_at(), refresh_interval_ms()))
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
  def handle_info({:entities_changed, %{entity_ids: entity_ids}}, state) do
    update_last_episodes_for(entity_ids)
    auto_track_new_entities(entity_ids)
    ReleaseTracking.complete_movie_tracking_for(entity_ids)
    {:noreply, state}
  end

  @impl true
  def handle_info({:containers_deleted, %{container_ids: container_ids}}, state) do
    ReleaseTracking.detach_library_containers(container_ids)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:refresh_all, state) do
    do_refresh_all()
    {:noreply, state}
  end

  defp do_refresh_all do
    Log.info(:library, "release tracking: starting refresh cycle")

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
          Log.info(:library, "refresh failed for #{item.name}: #{inspect(reason)}")
          []

        {:exit, reason} ->
          Log.info(:library, "refresh task crashed: #{inspect(reason)}")
          []
      end)

    # Phase 3: bounded parallel image backfill. Previously each commit
    # spawned its own Task.Supervisor.start_child, so N refreshed items
    # produced up to N concurrent image-download tasks competing for
    # bandwidth. Bound the fan-out the same way Phase 1 bounds TMDB
    # fetches.
    bulk_download_images(successful)

    ReleaseTracking.mark_past_releases_as_released()

    changed_ids = Enum.map(items, & &1.id)

    if changed_ids != [] do
      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        MediaCentaur.Topics.release_tracking_updates(),
        {:releases_updated, changed_ids}
      )
    end

    Log.info(:library, "release tracking: refresh complete (#{length(items)} items)")
  end

  defp bulk_download_images([]), do: :ok

  defp bulk_download_images(items_with_responses) do
    MediaCentaur.TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(
      items_with_responses,
      fn {item, response} -> download_images_sync(item, item.tmdb_id, response) end,
      max_concurrency: 4,
      timeout: 60_000,
      on_timeout: :kill_task
    )
    |> Stream.run()
  end

  defp fetch_for_item(%{media_type: :tv_series} = item) do
    case Client.get_tv(item.tmdb_id) do
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

  defp fetch_for_item(%{media_type: :movie} = item) do
    # `:movie` items conflate two distinct TMDB resources — series-style
    # collections (e.g. the Mario Bros collection) and solo movies (e.g.
    # the Mascot Cosmos movie). The schema enum can't tell them apart, so
    # we try /collection/{id} first and fall back to /movie/{id} on 404.
    case Client.get_collection(item.tmdb_id) do
      {:ok, response} ->
        new_releases = Helpers.fetch_collection_releases(response)
        {:ok, item, response, new_releases}

      {:error, {:http_error, 404, _}} ->
        case Client.get_movie(item.tmdb_id) do
          {:ok, response} ->
            new_releases = Helpers.fetch_movie_releases(response)
            {:ok, item, response, new_releases}

          {:error, reason} ->
            {:error, item, reason}
        end

      {:error, reason} ->
        {:error, item, reason}
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
    ReleaseTracking.delete_releases_for_item(item.id)

    Enum.each(new_releases, fn release ->
      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: release[:air_date],
        title: release[:title],
        season_number: release[:season_number],
        episode_number: release[:episode_number],
        release_type: release[:release_type],
        part_tmdb_id: release[:part_tmdb_id],
        released: release[:released] || false
      })
    end)

    ReleaseTracking.mark_in_library_releases(item)
    ReleaseTracking.sync_wants(item)
  end

  defp update_item_metadata(item, response) do
    name = response["name"] || response["title"] || item.name
    ReleaseTracking.update_item(item, %{name: name, last_refreshed_at: DateTime.utc_now()})
  end

  defp schedule_refresh(interval) do
    Process.send_after(self(), :refresh, interval)
  end

  defp schedule_sweep(interval) do
    Process.send_after(self(), :sweep, interval)
  end

  defp refresh_interval_ms do
    hours = MediaCentaur.Config.get(:release_tracking_refresh_interval_hours) || 6
    hours * 60 * 60 * 1000
  end

  defp sweep_interval_ms do
    minutes = MediaCentaur.Config.get(:release_tracking_sweep_interval_minutes) || 15
    minutes * 60 * 1000
  end

  defp do_sweep do
    Log.info(:library, "release tracking: sweep")
    ReleaseTracking.mark_past_releases_as_released()

    Enum.each(ReleaseTracking.list_watching_items(), fn item ->
      # The sweep is the want ledger's heartbeat (ADR-056): idempotent
      # sync per tick means the ledger self-backfills on first deploy
      # and self-heals after any missed seam.
      ReleaseTracking.sync_wants(item)
    end)

    # The drop planner's clock (ADR-056 Q2): the Reactor runs a tick
    # after every completed sweep, once the ledger sync is in.
    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.release_tracking_updates(),
      {:tracking_sweep_completed}
    )

    persist_last_swept_at()
    :ok
  end

  defp last_swept_at do
    case Settings.get_by_key(@last_swept_at_key) do
      {:ok, %{value: %{"timestamp" => iso}}} when is_binary(iso) ->
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
          :library,
          "release tracking: failed to persist last_swept_at — #{inspect(changeset.errors)}"
        )

        :ok
    end
  end

  defp link_unlinked_items(entity_ids) do
    tmdb_mappings = Library.tmdb_ids_for_tv_series(entity_ids)

    Enum.each(tmdb_mappings, fn {tv_series_id, tmdb_id_str} ->
      with {:ok, tmdb_id} <- Helpers.parse_tmdb_id(tmdb_id_str) do
        from(i in ReleaseTracking.Item,
          where:
            i.tmdb_id == ^tmdb_id and i.media_type == :tv_series and
              is_nil(i.library_container_id)
        )
        |> MediaCentaur.Repo.all()
        |> Enum.each(fn item ->
          case ReleaseTracking.update_item(item, %{
                 library_container_type: :tv_series,
                 library_container_id: tv_series_id
               }) do
            {:ok, _} ->
              Log.info(
                :library,
                "linked tracking item #{item.name} to library entity #{tv_series_id}"
              )

            {:error, changeset} ->
              Log.info(
                :library,
                "failed to link tracking item #{item.name}: #{inspect(changeset.errors)}"
              )
          end
        end)
      end
    end)
  end

  defp update_last_episodes_for(entity_ids) do
    link_unlinked_items(entity_ids)

    items =
      MediaCentaur.Repo.all(
        from(i in ReleaseTracking.Item, where: i.library_container_id in ^entity_ids)
      )

    existing_ids = batch_existing_container_ids(items)

    Enum.each(items, fn item ->
      if library_container_exists?(item, existing_ids) do
        if item.media_type == :tv_series do
          {season, episode} = Helpers.find_last_library_episode(item.library_container_id)

          if season != item.last_library_season || episode != item.last_library_episode do
            case ReleaseTracking.update_item(item, %{
                   last_library_season: season,
                   last_library_episode: episode
                 }) do
              {:ok, updated_item} ->
                ReleaseTracking.mark_in_library_releases(updated_item)
                ReleaseTracking.sync_wants(updated_item)

              {:error, changeset} ->
                Log.info(
                  :library,
                  "failed to update tracking item #{item.name}: #{inspect(changeset.errors)}"
                )
            end
          end
        end
      else
        Log.info(:library, "removing tracking item #{item.name} — library container deleted")
        ReleaseTracking.delete_item(item)
      end
    end)
  end

  # One IN-query per relevant table instead of one Repo.get per item — this
  # function is called from `handle_info({:entities_changed, ...})` so it
  # blocks the GenServer mailbox for the duration of the work.
  defp batch_existing_container_ids(items) do
    {tv_ids, movie_series_ids} =
      Enum.reduce(items, {[], []}, fn
        %{library_container_type: :tv_series, library_container_id: id}, {tvs, movies}
        when not is_nil(id) ->
          {[id | tvs], movies}

        %{library_container_type: :movie_series, library_container_id: id}, {tvs, movies}
        when not is_nil(id) ->
          {tvs, [id | movies]}

        _, acc ->
          acc
      end)

    %{
      tv_series: load_existing_ids(MediaCentaur.Library.TVSeries, tv_ids),
      movie_series: load_existing_ids(MediaCentaur.Library.MovieSeries, movie_series_ids)
    }
  end

  defp load_existing_ids(_schema, []), do: MapSet.new()

  defp load_existing_ids(schema, ids) do
    from(s in schema, where: s.id in ^ids, select: s.id)
    |> MediaCentaur.Repo.all()
    |> MapSet.new()
  end

  defp library_container_exists?(%{library_container_type: :tv_series, library_container_id: id}, %{
         tv_series: set
       }) do
    MapSet.member?(set, id)
  end

  defp library_container_exists?(%{library_container_type: :movie_series, library_container_id: id}, %{
         movie_series: set
       }) do
    MapSet.member?(set, id)
  end

  defp library_container_exists?(_, _), do: true

  @active_tv_statuses [:returning, :in_production, :planned]

  defp find_trackable_tv_series(entity_ids) do
    from(tv in MediaCentaur.Library.TVSeries,
      join: ext in MediaCentaur.Library.ExternalId,
      on:
        ext.owner_id == tv.id and ext.owner_type == :tv_series and
          ext.source == "tmdb",
      where: tv.id in ^entity_ids and tv.status in ^@active_tv_statuses,
      select: %{
        tv_series_id: tv.id,
        tmdb_id: ext.external_id,
        name: tv.name
      }
    )
    |> MediaCentaur.Repo.all()
    |> Enum.reject(fn %{tmdb_id: tmdb_id} ->
      case Helpers.parse_tmdb_id(tmdb_id) do
        {:ok, tmdb_id_int} -> ReleaseTracking.get_item_by_tmdb(tmdb_id_int, :tv_series) != nil
        :error -> false
      end
    end)
  end

  defp auto_track_tv_series(%{tv_series_id: tv_series_id, tmdb_id: tmdb_id_str, name: name}) do
    case Helpers.parse_tmdb_id(tmdb_id_str) do
      {:ok, tmdb_id} ->
        do_auto_track_tv_series(tv_series_id, tmdb_id, name)

      :error ->
        Log.info(
          :library,
          "auto-track skipped for #{name}: unparseable TMDB id #{inspect(tmdb_id_str)}"
        )
    end
  end

  defp do_auto_track_tv_series(tv_series_id, tmdb_id, name) do
    case Client.get_tv(tmdb_id) do
      {:ok, response} ->
        {last_season, last_episode} = Helpers.find_last_library_episode(tv_series_id)
        releases = Helpers.fetch_tv_releases(tmdb_id, last_season, last_episode, response)

        {:ok, item} =
          ReleaseTracking.track_item(%{
            tmdb_id: tmdb_id,
            media_type: :tv_series,
            name: response["name"] || name,
            source: :library,
            library_container_type: :tv_series,
            library_container_id: tv_series_id,
            last_refreshed_at: DateTime.utc_now(),
            last_library_season: last_season,
            last_library_episode: last_episode
          })

        Enum.each(releases, fn release ->
          ReleaseTracking.create_release!(%{
            item_id: item.id,
            air_date: release[:air_date],
            title: release[:title],
            season_number: release[:season_number],
            episode_number: release[:episode_number],
            released: release[:released] || false
          })
        end)

        ReleaseTracking.mark_in_library_releases(item)
        ReleaseTracking.sync_wants(item)

        ReleaseTracking.create_event!(%{
          item_id: item.id,
          item_name: item.name,
          event_type: :began_tracking,
          description: "Now tracking #{item.name}"
        })

        download_images_async(item, tmdb_id, response)

        broadcast_tracking_update([item.id])

        Log.info(
          :library,
          "auto-tracked #{item.name} (TMDB #{tmdb_id}) — source: library"
        )

      {:error, reason} ->
        Log.info(:library, "auto-track failed for #{name} (TMDB #{tmdb_id}): #{inspect(reason)}")
    end
  end

  # Backfill of images that are missing from the item but available in the
  # TMDB response. The `pending_image_downloads/2` filter makes this
  # idempotent — already-fetched images skip the network entirely.
  #
  # Two entry points:
  #  * `download_images_async/3` — fire-and-forget single-item case (used
  #    by auto-track, where exactly one item is being onboarded).
  #  * `download_images_sync/3` — synchronous body, called by Phase 3 of
  #    `do_refresh_all` under a bounded `async_stream` so a refresh cycle
  #    over N items doesn't fan out to N concurrent download tasks.
  defp download_images_async(item, tmdb_id, response) do
    if pending_image_downloads(item, response) != [] do
      Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
        download_images_sync(item, tmdb_id, response)
      end)
    end

    :ok
  end

  defp download_images_sync(item, tmdb_id, response) do
    pending = pending_image_downloads(item, response)

    attrs =
      Enum.reduce(pending, %{}, fn {tmdb_path, attr_key, downloader}, acc ->
        case downloader.(tmdb_id, tmdb_path) do
          {:ok, path} when is_binary(path) -> Map.put(acc, attr_key, path)
          _ -> acc
        end
      end)

    if attrs != %{}, do: ReleaseTracking.update_item(item, attrs)
    :ok
  end

  # Returns `[{tmdb_source_path, attr_key, downloader}]` for every image role
  # the item still lacks AND that TMDB has a path for.
  defp pending_image_downloads(item, response) do
    [
      {item.poster_path, ReleaseTracking.Extractor.extract_poster_path(response), :poster_path,
       &ReleaseTracking.ImageStore.download_poster/2},
      {item.backdrop_path, response["backdrop_path"], :backdrop_path,
       &ReleaseTracking.ImageStore.download_backdrop/2},
      {item.logo_path, ReleaseTracking.Extractor.extract_logo_path(response), :logo_path,
       &ReleaseTracking.ImageStore.download_logo/2}
    ]
    |> Enum.filter(fn {current, tmdb_path, _, _} -> is_nil(current) and is_binary(tmdb_path) end)
    |> Enum.map(fn {_, tmdb_path, attr_key, downloader} -> {tmdb_path, attr_key, downloader} end)
  end

  defp broadcast_tracking_update(item_ids) do
    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.release_tracking_updates(),
      {:releases_updated, item_ids}
    )
  end
end
