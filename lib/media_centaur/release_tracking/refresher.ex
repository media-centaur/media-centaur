defmodule MediaCentaur.ReleaseTracking.Refresher do
  @moduledoc """
  GenServer that periodically refreshes TMDB data for all tracked items.
  """
  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.{Extractor, Differ}
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

    Enum.each(items, fn item ->
      case do_refresh_item(item) do
        :ok ->
          :ok

        {:error, reason} ->
          Log.info(:library, "refresh failed for #{item.name}: #{inspect(reason)}")
      end
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

        seasons_to_fetch = seasons_to_fetch(response, last_season)

        new_releases =
          seasons_to_fetch
          |> Enum.flat_map(fn season_num ->
            case Client.get_season(item.tmdb_id, season_num) do
              {:ok, season_data} ->
                Extractor.extract_episodes_since(season_data, last_season, last_episode)

              {:error, _} ->
                []
            end
          end)
          |> mark_released()

        # Fall back to next_episode_to_air if season data returned nothing
        new_releases =
          if new_releases == [] do
            Extractor.extract_tv_releases(response) |> mark_released()
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
          |> Enum.map(fn release ->
            %{
              air_date: release.air_date,
              title: release.title,
              season_number: nil,
              episode_number: nil
            }
          end)

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

  defp seasons_to_fetch(response, last_season) do
    total_seasons = response["number_of_seasons"] || 1
    next_ep = response["next_episode_to_air"]
    next_season = if next_ep, do: next_ep["season_number"], else: total_seasons

    seasons = [max(last_season, 1)]
    seasons = if next_season > hd(seasons), do: seasons ++ [next_season], else: seasons
    Enum.uniq(seasons)
  end

  defp mark_released(releases) do
    today = Date.utc_today()

    Enum.map(releases, fn release ->
      released = release.air_date != nil && Date.compare(release.air_date, today) != :gt
      Map.put(release, :released, released)
    end)
  end

  defp update_last_episodes_for(entity_ids) do
    import Ecto.Query

    # Find all tracking items referencing any of the changed library entities
    items =
      from(i in ReleaseTracking.Item,
        where: i.library_entity_id in ^entity_ids
      )
      |> MediaCentaur.Repo.all()

    Enum.each(items, fn item ->
      if library_entity_exists?(item) do
        # Entity still exists — update last episode if it's a TV series
        if item.media_type == :tv_series do
          {season, episode} = find_last_library_episode(item.library_entity_id)

          if season != item.last_library_season || episode != item.last_library_episode do
            ReleaseTracking.update_item(item, %{
              last_library_season: season,
              last_library_episode: episode
            })
          end
        end
      else
        # Entity was deleted — remove tracking item
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

  defp find_last_library_episode(nil), do: {0, 0}

  defp find_last_library_episode(library_entity_id) do
    import Ecto.Query

    result =
      from(e in MediaCentaur.Library.Episode,
        join: s in MediaCentaur.Library.Season,
        on: e.season_id == s.id,
        where: s.tv_series_id == ^library_entity_id,
        select: {s.season_number, e.episode_number},
        order_by: [desc: s.season_number, desc: e.episode_number],
        limit: 1
      )
      |> MediaCentaur.Repo.one()

    result || {0, 0}
  end
end
