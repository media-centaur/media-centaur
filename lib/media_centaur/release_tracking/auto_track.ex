defmodule MediaCentaur.ReleaseTracking.AutoTrack do
  @moduledoc """
  Onboards a library TV series into release tracking without the user
  asking: fetches the series from TMDB, creates the tracking item linked
  to the library container, seeds its releases and wants, and backfills
  artwork. Runs from `ReleaseTracking.AutoTrackJob`, never inline with
  the library event that triggered it.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Helpers
  alias MediaCentaur.TMDB.Client
  alias MediaCentaur.TMDB.Identifiers
  alias MediaCentaur.TMDB.Mapper

  @active_tv_statuses [:returning, :in_production, :planned]

  @doc """
  Starts tracking every TV series among `entity_ids` that has a TMDB id,
  an active TMDB status and no tracking item yet. One TMDB fetch per
  series; a failed fetch is logged and skipped.
  """
  @spec run([Ecto.UUID.t()]) :: :ok
  def run(entity_ids) do
    Enum.each(find_trackable_tv_series(entity_ids), &auto_track_tv_series/1)
  end

  defp find_trackable_tv_series(entity_ids) do
    active = Library.Containers.list_tv_series(entity_ids, status: @active_tv_statuses)
    tmdb_ids = Map.new(Library.ExternalIds.tmdb_ids_for_tv_series(Enum.map(active, & &1.id)))

    active
    |> Enum.flat_map(fn tv ->
      case Map.fetch(tmdb_ids, tv.id) do
        {:ok, tmdb_id} -> [%{tv_series_id: tv.id, tmdb_id: tmdb_id, name: tv.name}]
        :error -> []
      end
    end)
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
          :acquisition,
          "auto-track skipped for #{name}: unparseable TMDB id #{inspect(tmdb_id_str)}"
        )
    end
  end

  defp do_auto_track_tv_series(tv_series_id, tmdb_id, name) do
    case Client.get_tv(tmdb_id) do
      {:ok, response} ->
        {last_season, last_episode} = Helpers.find_last_library_episode(tv_series_id)
        identifiers = Identifiers.from_payload(:tv, response)
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
            origin_country: response["origin_country"],
            imdb_id: identifiers.imdb_id,
            tvdb_id: identifiers.tvdb_id,
            original_title: Mapper.original_title(response),
            last_library_season: last_season,
            last_library_episode: last_episode
          })

        ReleaseTracking.replace_releases!(item, releases, &ReleaseTracking.persist_release!/2)

        ReleaseTracking.mark_in_library_releases(item)
        ReleaseTracking.sync_wants(item)

        ReleaseTracking.create_event!(%{
          item_id: item.id,
          item_name: item.name,
          event_type: :began_tracking,
          description: "Now tracking #{item.name}"
        })

        Helpers.download_images_async(item, tmdb_id, response)

        broadcast_tracking_update([item.id])

        Log.info(
          :acquisition,
          "auto-tracked #{item.name} (TMDB #{tmdb_id}) — source: library"
        )

      {:error, reason} ->
        Log.info(:acquisition, "auto-track failed for #{name} (TMDB #{tmdb_id}): #{inspect(reason)}")
    end
  end

  # Image backfill (poster/backdrop/logo) lives in
  # `ReleaseTracking.Helpers` — shared with Scanner so both onboard the
  # full role set idempotently.

  defp broadcast_tracking_update(item_ids) do
    MediaCentaur.Topics.publish(
      MediaCentaur.Topics.release_tracking_updates(),
      {:releases_updated, item_ids}
    )
  end
end
