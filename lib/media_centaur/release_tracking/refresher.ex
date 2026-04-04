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
        old_releases = ReleaseTracking.list_releases_for_item(item.id)
        new_releases = Extractor.extract_tv_releases(response)

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
        episode_number: release[:episode_number]
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
end
