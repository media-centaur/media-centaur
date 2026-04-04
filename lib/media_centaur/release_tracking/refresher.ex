defmodule MediaCentaur.ReleaseTracking.Refresher do
  @moduledoc """
  GenServer that periodically refreshes TMDB data for all tracked items.
  """
  use GenServer

  import Ecto.Query
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.{Extractor, Differ, Helpers}
  alias MediaCentaur.TMDB.Client

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def refresh_all do
    GenServer.cast(__MODULE__, :refresh_all)
  end

  @doc "Refresh a single item. Can be called directly in tests."
  def refresh_item(%ReleaseTracking.Item{} = item) do
    do_refresh_item(item)
  end

  @doc "Update tracking items when library entities change. Testable without GenServer."
  def refresh_item_tracking_for(entity_ids) do
    update_last_episodes_for(entity_ids)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_updates())
    interval = refresh_interval_ms()
    schedule_refresh(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:refresh, state) do
    do_refresh_all()
    schedule_refresh(state.interval)
    {:noreply, state}
  end

  @impl true
  def handle_info({:entities_changed, entity_ids}, state) do
    update_last_episodes_for(entity_ids)
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

    MediaCentaur.TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(items, &do_refresh_item/1,
      max_concurrency: 4,
      timeout: 30_000
    )
    |> Enum.each(fn
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> Log.info(:library, "refresh failed: #{inspect(reason)}")
      {:exit, reason} -> Log.info(:library, "refresh task crashed: #{inspect(reason)}")
    end)

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

  defp do_refresh_item(%{media_type: :tv_series} = item) do
    case Client.get_tv(item.tmdb_id) do
      {:ok, response} ->
        last_season = item.last_library_season
        last_episode = item.last_library_episode

        seasons = Helpers.seasons_to_fetch(response, last_season)

        new_releases =
          seasons
          |> Enum.flat_map(fn season_num ->
            case Client.get_season(item.tmdb_id, season_num) do
              {:ok, season_data} ->
                Extractor.extract_episodes_since(season_data, last_season, last_episode)

              {:error, _} ->
                []
            end
          end)
          |> Helpers.mark_released()

        # Fall back to next_episode_to_air if season data returned nothing
        new_releases =
          if new_releases == [] do
            Extractor.extract_tv_releases(response) |> Helpers.mark_released()
          else
            new_releases
          end

        old_releases = ReleaseTracking.list_releases_for_item(item.id)
        events = Differ.diff(old_releases, new_releases)
        write_events(item, events)
        replace_releases(item, new_releases)
        update_item_metadata(item, response)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_refresh_item(%{media_type: :movie} = item) do
    case Client.get_collection(item.tmdb_id) do
      {:ok, response} ->
        old_releases = ReleaseTracking.list_releases_for_item(item.id)

        new_releases =
          Extractor.extract_collection_releases(response)
          |> Helpers.normalize_collection_releases()

        events = Differ.diff(old_releases, new_releases)
        write_events(item, events)
        replace_releases(item, new_releases)
        update_item_metadata(item, response)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_events(item, events) do
    Enum.each(events, fn event ->
      ReleaseTracking.create_event!(%{
        item_id: item.id,
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
  end

  defp update_item_metadata(item, response) do
    name = response["name"] || response["title"] || item.name
    ReleaseTracking.update_item(item, %{name: name, last_refreshed_at: DateTime.utc_now()})
  end

  defp schedule_refresh(interval) do
    Process.send_after(self(), :refresh, interval)
  end

  defp refresh_interval_ms do
    hours = MediaCentaur.Config.get(:release_tracking_refresh_interval_hours) || 24
    hours * 60 * 60 * 1000
  end

  defp update_last_episodes_for(entity_ids) do
    items =
      from(i in ReleaseTracking.Item,
        where: i.library_entity_id in ^entity_ids
      )
      |> MediaCentaur.Repo.all()

    Enum.each(items, fn item ->
      if library_entity_exists?(item) do
        if item.media_type == :tv_series do
          {season, episode} = Helpers.find_last_library_episode(item.library_entity_id)

          if season != item.last_library_season || episode != item.last_library_episode do
            ReleaseTracking.update_item(item, %{
              last_library_season: season,
              last_library_episode: episode
            })
          end
        end
      else
        Log.info(:library, "removing tracking item #{item.name} — library entity deleted")
        ReleaseTracking.delete_item(item)
      end
    end)
  end

  defp library_entity_exists?(%{media_type: :tv_series, library_entity_id: id}) do
    MediaCentaur.Repo.get(MediaCentaur.Library.TVSeries, id) != nil
  end

  defp library_entity_exists?(%{media_type: :movie, library_entity_id: id}) do
    MediaCentaur.Repo.get(MediaCentaur.Library.MovieSeries, id) != nil
  end

  defp library_entity_exists?(_), do: true
end
