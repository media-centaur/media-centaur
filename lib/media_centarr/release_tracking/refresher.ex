defmodule MediaCentarr.ReleaseTracking.Refresher do
  @moduledoc """
  GenServer that periodically refreshes TMDB data for all tracked items.
  """
  use GenServer

  import Ecto.Query
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Library
  alias MediaCentarr.ReleaseTracking
  alias MediaCentarr.ReleaseTracking.{Differ, Helpers}
  alias MediaCentarr.TMDB.Client

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
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.library_updates())
    schedule_refresh(refresh_interval_ms())
    {:ok, %{}}
  end

  @impl true
  def handle_info(:refresh, state) do
    do_refresh_all()
    schedule_refresh(refresh_interval_ms())
    {:noreply, state}
  end

  @impl true
  def handle_info({:entities_changed, entity_ids}, state) do
    update_last_episodes_for(entity_ids)
    auto_track_new_entities(entity_ids)
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
      MediaCentarr.TaskSupervisor
      |> Task.Supervisor.async_stream_nolink(items, &fetch_for_item/1,
        max_concurrency: 4,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    # Phase 2: serialized commits. SQLite is a single-writer database; a
    # single commit loop avoids lock contention and the rollback that
    # comes with four concurrent write transactions.
    Enum.each(fetched, fn
      {:ok, {:ok, item, response, new_releases}} ->
        commit_refresh(item, response, new_releases)

      {:ok, {:error, item, reason}} ->
        Log.info(:library, "refresh failed for #{item.name}: #{inspect(reason)}")

      {:exit, reason} ->
        Log.info(:library, "refresh task crashed: #{inspect(reason)}")
    end)

    ReleaseTracking.mark_past_releases_as_released()

    changed_ids = Enum.map(items, & &1.id)

    if changed_ids != [] do
      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        MediaCentarr.Topics.release_tracking_updates(),
        {:releases_updated, changed_ids}
      )
    end

    Log.info(:library, "release tracking: refresh complete (#{length(items)} items)")
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
    case Client.get_collection(item.tmdb_id) do
      {:ok, response} ->
        new_releases = Helpers.fetch_collection_releases(response)
        {:ok, item, response, new_releases}

      {:error, reason} ->
        {:error, item, reason}
    end
  end

  defp commit_refresh(item, response, new_releases) do
    old_releases = ReleaseTracking.list_releases_for_item(item.id)
    events = Differ.diff(old_releases, new_releases)
    write_events(item, events)
    replace_releases(item, new_releases)
    update_item_metadata(item, response)
    broadcast_releases_ready(item)
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
        released: release[:released] || false
      })
    end)

    ReleaseTracking.mark_in_library_releases(item)
  end

  defp update_item_metadata(item, response) do
    name = response["name"] || response["title"] || item.name
    ReleaseTracking.update_item(item, %{name: name, last_refreshed_at: DateTime.utc_now()})
  end

  defp schedule_refresh(interval) do
    Process.send_after(self(), :refresh, interval)
  end

  defp refresh_interval_ms do
    hours = MediaCentarr.Config.get(:release_tracking_refresh_interval_hours) || 24
    hours * 60 * 60 * 1000
  end

  defp link_unlinked_items(entity_ids) do
    tmdb_mappings = Library.tmdb_external_ids_for_tv_series(entity_ids)

    Enum.each(tmdb_mappings, fn {tv_series_id, tmdb_id_str} ->
      tmdb_id = String.to_integer(tmdb_id_str)

      from(i in ReleaseTracking.Item,
        where: i.tmdb_id == ^tmdb_id and i.media_type == :tv_series and is_nil(i.library_entity_id)
      )
      |> MediaCentarr.Repo.all()
      |> Enum.each(fn item ->
        case ReleaseTracking.update_item(item, %{library_entity_id: tv_series_id}) do
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
    end)
  end

  defp update_last_episodes_for(entity_ids) do
    link_unlinked_items(entity_ids)

    items =
      MediaCentarr.Repo.all(from(i in ReleaseTracking.Item, where: i.library_entity_id in ^entity_ids))

    Enum.each(items, fn item ->
      if library_entity_exists?(item) do
        if item.media_type == :tv_series do
          {season, episode} = Helpers.find_last_library_episode(item.library_entity_id)

          if season != item.last_library_season || episode != item.last_library_episode do
            case ReleaseTracking.update_item(item, %{
                   last_library_season: season,
                   last_library_episode: episode
                 }) do
              {:ok, updated_item} ->
                ReleaseTracking.mark_in_library_releases(updated_item)

              {:error, changeset} ->
                Log.info(
                  :library,
                  "failed to update tracking item #{item.name}: #{inspect(changeset.errors)}"
                )
            end
          end
        end
      else
        Log.info(:library, "removing tracking item #{item.name} — library entity deleted")
        ReleaseTracking.delete_item(item)
      end
    end)
  end

  defp library_entity_exists?(%{media_type: :tv_series, library_entity_id: id}) do
    MediaCentarr.Repo.get(MediaCentarr.Library.TVSeries, id) != nil
  end

  defp library_entity_exists?(%{media_type: :movie, library_entity_id: id}) do
    MediaCentarr.Repo.get(MediaCentarr.Library.MovieSeries, id) != nil
  end

  defp library_entity_exists?(_), do: true

  @active_tv_statuses [:returning, :in_production, :planned]

  defp find_trackable_tv_series(entity_ids) do
    from(tv in MediaCentarr.Library.TVSeries,
      join: ext in MediaCentarr.Library.ExternalId,
      on: ext.tv_series_id == tv.id and ext.source == "tmdb",
      where: tv.id in ^entity_ids and tv.status in ^@active_tv_statuses,
      select: %{
        tv_series_id: tv.id,
        tmdb_id: ext.external_id,
        name: tv.name
      }
    )
    |> MediaCentarr.Repo.all()
    |> Enum.reject(fn %{tmdb_id: tmdb_id} ->
      tmdb_id_int = String.to_integer(tmdb_id)
      ReleaseTracking.get_item_by_tmdb(tmdb_id_int, :tv_series) != nil
    end)
  end

  defp auto_track_tv_series(%{tv_series_id: tv_series_id, tmdb_id: tmdb_id_str, name: name}) do
    tmdb_id = String.to_integer(tmdb_id_str)

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
            library_entity_id: tv_series_id,
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

  defp download_images_async(item, tmdb_id, response) do
    poster_path = ReleaseTracking.Extractor.extract_poster_path(response)
    backdrop_path = response["backdrop_path"]

    if poster_path || backdrop_path do
      Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
        attrs = %{}

        attrs =
          case ReleaseTracking.ImageStore.download_poster(tmdb_id, poster_path) do
            {:ok, path} when is_binary(path) -> Map.put(attrs, :poster_path, path)
            _ -> attrs
          end

        attrs =
          case ReleaseTracking.ImageStore.download_backdrop(tmdb_id, backdrop_path) do
            {:ok, path} when is_binary(path) -> Map.put(attrs, :backdrop_path, path)
            _ -> attrs
          end

        if attrs != %{}, do: ReleaseTracking.update_item(item, attrs)
      end)
    end
  end

  defp broadcast_tracking_update(item_ids) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      MediaCentarr.Topics.release_tracking_updates(),
      {:releases_updated, item_ids}
    )
  end

  @doc """
  Broadcasts one `{:release_ready, item, release}` per release of `item`
  that is available (air_date on or before today) and not yet in the library.

  Public so the unit test can exercise it without going through TMDB.
  Idempotent — receivers (e.g. `Acquisition`) must handle re-broadcasts;
  refreshes can fire repeatedly while a release stays available-and-ungrabbed.
  """
  def broadcast_releases_ready(item) do
    today = Date.utc_today()

    item.id
    |> ReleaseTracking.list_releases_for_item()
    |> Enum.filter(&release_ready?(&1, today))
    |> Enum.each(fn release ->
      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        MediaCentarr.Topics.release_tracking_updates(),
        {:release_ready, item, release}
      )
    end)
  end

  defp release_ready?(release, today) do
    release.air_date != nil and
      Date.compare(release.air_date, today) != :gt and
      not release.in_library
  end
end
