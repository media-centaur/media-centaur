defmodule MediaCentaur.ReleaseTracking.Scanner do
  @moduledoc """
  Scans the library for items with TMDB external IDs and creates tracking
  items for any with upcoming releases.
  """

  import Ecto.Query
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Repo
  alias MediaCentaur.Library.ExternalId
  alias MediaCentaur.TMDB.Client
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Extractor

  def scan do
    external_ids = load_library_tmdb_ids()
    Log.info(:library, "release tracking scan: #{length(external_ids)} TMDB IDs found")

    results =
      Enum.reduce(external_ids, %{tracked: 0, skipped: 0, errors: 0}, fn ext_id, acc ->
        case process_external_id(ext_id) do
          :tracked -> %{acc | tracked: acc.tracked + 1}
          :skipped -> %{acc | skipped: acc.skipped + 1}
          :error -> %{acc | errors: acc.errors + 1}
        end
      end)

    Log.info(:library, "release tracking scan complete: #{inspect(results)}")
    {:ok, results}
  end

  defp load_library_tmdb_ids do
    from(e in ExternalId,
      where: e.source in ["tmdb", "tmdb_collection"],
      select: %{
        source: e.source,
        external_id: e.external_id,
        tv_series_id: e.tv_series_id,
        movie_series_id: e.movie_series_id,
        movie_id: e.movie_id
      }
    )
    |> Repo.all()
  end

  defp process_external_id(%{source: "tmdb", tv_series_id: tv_series_id} = ext_id)
       when not is_nil(tv_series_id) do
    tmdb_id = parse_tmdb_id(ext_id.external_id)

    if already_tracked?(tmdb_id, :tv_series) do
      :skipped
    else
      process_tv_series(tmdb_id, tv_series_id)
    end
  end

  defp process_external_id(
         %{source: "tmdb_collection", movie_series_id: movie_series_id} = ext_id
       )
       when not is_nil(movie_series_id) do
    collection_id = parse_tmdb_id(ext_id.external_id)

    if already_tracked?(collection_id, :movie) do
      :skipped
    else
      process_collection(collection_id, movie_series_id)
    end
  end

  defp process_external_id(_), do: :skipped

  defp process_tv_series(tmdb_id, library_entity_id) do
    case Client.get_tv(tmdb_id) do
      {:ok, response} ->
        status = Extractor.extract_tv_status(response)

        if status in [:returning, :in_production, :planned] do
          releases = Extractor.extract_tv_releases(response)

          create_tracked_item(
            tmdb_id,
            :tv_series,
            response["name"],
            library_entity_id,
            releases,
            response
          )

          :tracked
        else
          :skipped
        end

      {:error, _reason} ->
        :error
    end
  end

  defp process_collection(collection_id, library_entity_id) do
    case Client.get_collection(collection_id) do
      {:ok, response} ->
        releases = Extractor.extract_collection_releases(response)

        if releases != [] do
          collection_releases =
            Enum.map(releases, fn release ->
              %{
                air_date: release.air_date,
                title: release.title,
                season_number: nil,
                episode_number: nil
              }
            end)

          create_tracked_item(
            collection_id,
            :movie,
            response["name"],
            library_entity_id,
            collection_releases,
            response
          )

          :tracked
        else
          :skipped
        end

      {:error, _reason} ->
        :error
    end
  end

  defp create_tracked_item(tmdb_id, media_type, name, library_entity_id, releases, response) do
    {:ok, item} =
      ReleaseTracking.track_item(%{
        tmdb_id: tmdb_id,
        media_type: media_type,
        name: name,
        source: :library,
        library_entity_id: library_entity_id,
        last_refreshed_at: DateTime.utc_now()
      })

    Enum.each(releases, fn release ->
      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: release[:air_date],
        title: release[:title],
        season_number: release[:season_number],
        episode_number: release[:episode_number]
      })
    end)

    ReleaseTracking.create_event!(%{
      item_id: item.id,
      event_type: :item_added,
      description: "Now tracking #{name}"
    })

    poster_path = Extractor.extract_poster_path(response)

    if poster_path do
      Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
        case ReleaseTracking.ImageStore.download_poster(tmdb_id, poster_path) do
          {:ok, path} when is_binary(path) ->
            ReleaseTracking.update_item(item, %{poster_path: path})

          _ ->
            :ok
        end
      end)
    end

    :ok
  end

  defp already_tracked?(tmdb_id, media_type) do
    ReleaseTracking.get_item_by_tmdb(tmdb_id, media_type) != nil
  end

  defp parse_tmdb_id(id) when is_integer(id), do: id
  defp parse_tmdb_id(id) when is_binary(id), do: String.to_integer(id)
end
