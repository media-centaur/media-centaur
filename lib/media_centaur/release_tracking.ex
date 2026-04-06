defmodule MediaCentaur.ReleaseTracking do
  @moduledoc """
  Bounded context for tracking upcoming movie and TV releases via TMDB.

  Fully isolated from the Library context — owns its own tables, images,
  and TMDB extraction logic.
  """

  import Ecto.Query
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Repo
  alias MediaCentaur.ReleaseTracking.{Item, Release, Event, Extractor, Helpers, ImageStore}
  alias MediaCentaur.TMDB.Client

  # --- Items ---

  def track_item(attrs) do
    Item.create_changeset(attrs) |> Repo.insert()
  end

  def track_item!(attrs) do
    Item.create_changeset(attrs) |> Repo.insert!()
  end

  def ignore_item(%Item{} = item) do
    Item.update_changeset(item, %{status: :ignored}) |> Repo.update()
  end

  def watch_item(%Item{} = item) do
    Item.update_changeset(item, %{status: :watching}) |> Repo.update()
  end

  def update_item(%Item{} = item, attrs) do
    Item.update_changeset(item, attrs) |> Repo.update()
  end

  def get_item(id), do: Repo.get(Item, id)

  def get_item_by_tmdb(tmdb_id, media_type) do
    Repo.get_by(Item, tmdb_id: tmdb_id, media_type: media_type)
  end

  def delete_item(%Item{} = item) do
    item_id = item.id
    result = Repo.delete(item)
    broadcast_releases_updated([item_id])
    result
  end

  def list_watching_items do
    from(i in Item,
      where: i.status == :watching,
      order_by: [asc: i.name],
      preload: [:releases]
    )
    |> Repo.all()
  end

  def list_all_items do
    from(i in Item, order_by: [asc: i.name], preload: [:releases])
    |> Repo.all()
  end

  def tracking_status({tmdb_id, media_type}) do
    case Repo.get_by(Item, tmdb_id: tmdb_id, media_type: media_type) do
      nil -> nil
      item -> item.status
    end
  end

  # --- Suggestions ---

  @active_tv_statuses [:returning, :in_production, :planned]

  @doc """
  Returns untracked library TV series with active TMDB status and external IDs.
  Used to populate the suggestions section of the Track New Show modal.
  """
  def suggest_trackable_items do
    tracked_tmdb_ids =
      from(i in Item, select: {i.tmdb_id, i.media_type})
      |> Repo.all()
      |> MapSet.new()

    from(tv in MediaCentaur.Library.TVSeries,
      join: ext in MediaCentaur.Library.ExternalId,
      on: ext.tv_series_id == tv.id and ext.source == "tmdb",
      left_join: img in MediaCentaur.Library.Image,
      on: img.tv_series_id == tv.id and img.role == "poster",
      where: tv.status in ^@active_tv_statuses or is_nil(tv.status),
      select: %{
        tv_series_id: tv.id,
        tmdb_id: ext.external_id,
        name: tv.name,
        media_type: :tv_series,
        poster_url: img.content_url
      }
    )
    |> Repo.all()
    |> Enum.reject(fn %{tmdb_id: tmdb_id} ->
      tmdb_id_int = String.to_integer(tmdb_id)
      MapSet.member?(tracked_tmdb_ids, {tmdb_id_int, :tv_series})
    end)
  end

  # --- Search ---

  @doc """
  Searches TMDB for both movies and TV shows in parallel. Returns a unified
  list of results with media_type, tmdb_id, name, year, poster_path, and
  an already_tracked flag.
  """
  def search_tmdb(query) do
    movie_task = Task.async(fn -> Client.search_movie(query) end)
    tv_task = Task.async(fn -> Client.search_tv(query) end)

    movie_results =
      case Task.await(movie_task, 10_000) do
        {:ok, results} -> Enum.map(results, &normalize_movie_result/1)
        _ -> []
      end

    tv_results =
      case Task.await(tv_task, 10_000) do
        {:ok, results} -> Enum.map(results, &normalize_tv_result/1)
        _ -> []
      end

    tracked_tmdb_ids =
      from(i in Item, select: {i.tmdb_id, i.media_type})
      |> Repo.all()
      |> MapSet.new()

    (movie_results ++ tv_results)
    |> Enum.map(fn result ->
      tracked = MapSet.member?(tracked_tmdb_ids, {result.tmdb_id, result.media_type})
      Map.put(result, :already_tracked, tracked)
    end)
  end

  defp normalize_movie_result(tmdb) do
    %{
      tmdb_id: tmdb["id"],
      media_type: :movie,
      name: tmdb["title"],
      year: extract_year(tmdb["release_date"]),
      poster_path: tmdb["poster_path"]
    }
  end

  defp normalize_tv_result(tmdb) do
    %{
      tmdb_id: tmdb["id"],
      media_type: :tv_series,
      name: tmdb["name"],
      year: extract_year(tmdb["first_air_date"]),
      poster_path: tmdb["poster_path"]
    }
  end

  defp extract_year(nil), do: nil
  defp extract_year(""), do: nil
  defp extract_year(<<year::binary-size(4), _::binary>>), do: year

  # --- Track from search ---

  @doc """
  Creates a tracking item from a search result. Used by the Track New Show modal.

  Accepts a result map (%{tmdb_id, media_type, name, poster_path}) and options:
  - For TV: %{start_season: n, start_episode: n} to set tracking offset
  - For movies: %{} (no options needed)
  """
  def track_from_search(result, opts \\ %{}) do
    start_season = Map.get(opts, :start_season, 0)
    start_episode = Map.get(opts, :start_episode, 0)

    case do_track_from_search(result, start_season, start_episode) do
      {:ok, item} ->
        broadcast_releases_updated([item.id])
        {:ok, item}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_track_from_search(%{media_type: :tv_series} = result, start_season, start_episode) do
    case Client.get_tv(result.tmdb_id) do
      {:ok, response} ->
        all_releases =
          Helpers.fetch_tv_releases(result.tmdb_id, start_season, start_episode, response)

        # "All upcoming" (0,0) = only future episodes. Custom scope = include released too.
        releases =
          if start_season == 0 && start_episode == 0 do
            Enum.reject(all_releases, & &1[:released])
          else
            all_releases
          end

        {:ok, item} =
          track_item(%{
            tmdb_id: result.tmdb_id,
            media_type: :tv_series,
            name: response["name"] || result.name,
            source: :manual,
            last_refreshed_at: DateTime.utc_now(),
            last_library_season: start_season,
            last_library_episode: start_episode
          })

        persist_releases(item, releases)
        create_began_tracking_event(item)
        schedule_image_downloads(item, result.tmdb_id, response)

        {:ok, item}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_track_from_search(%{media_type: :movie} = result, _start_season, _start_episode) do
    case Client.get_movie(result.tmdb_id) do
      {:ok, response} ->
        {:ok, item} =
          track_item(%{
            tmdb_id: result.tmdb_id,
            media_type: :movie,
            name: response["title"] || result.name,
            source: :manual,
            last_refreshed_at: DateTime.utc_now()
          })

        releases = Extractor.extract_movie_release_dates(response)
        persist_movie_releases(item, releases)

        create_began_tracking_event(item)
        schedule_image_downloads(item, result.tmdb_id, response)

        {:ok, item}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_movie_releases(item, releases) do
    today = Date.utc_today()

    Enum.each(releases, fn release ->
      released = release.air_date != nil && Date.compare(release.air_date, today) != :gt

      create_release!(%{
        item_id: item.id,
        air_date: release.air_date,
        title: release.title,
        release_type: release.release_type,
        released: released
      })
    end)
  end

  defp broadcast_releases_updated(item_ids) do
    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.release_tracking_updates(),
      {:releases_updated, item_ids}
    )
  end

  defp persist_releases(item, releases) do
    Enum.each(releases, fn release ->
      create_release!(%{
        item_id: item.id,
        air_date: release[:air_date],
        title: release[:title],
        season_number: release[:season_number],
        episode_number: release[:episode_number],
        released: release[:released] || false
      })
    end)

    mark_in_library_releases(item)
  end

  defp create_began_tracking_event(item) do
    create_event!(%{
      item_id: item.id,
      item_name: item.name,
      event_type: :began_tracking,
      description: "Now tracking #{item.name}"
    })
  end

  defp schedule_image_downloads(item, tmdb_id, response) do
    poster_path = Extractor.extract_poster_path(response)
    backdrop_path = response["backdrop_path"]

    if poster_path || backdrop_path do
      Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
        attrs = %{}

        attrs =
          case ImageStore.download_poster(tmdb_id, poster_path) do
            {:ok, path} when is_binary(path) -> Map.put(attrs, :poster_path, path)
            _ -> attrs
          end

        attrs =
          case ImageStore.download_backdrop(tmdb_id, backdrop_path) do
            {:ok, path} when is_binary(path) -> Map.put(attrs, :backdrop_path, path)
            _ -> attrs
          end

        if attrs != %{} do
          update_item(item, attrs)
          broadcast_releases_updated([item.id])
        end
      end)
    end
  end

  # --- Releases ---

  def create_release(attrs) do
    Release.create_changeset(attrs) |> Repo.insert()
  end

  def create_release!(attrs) do
    Release.create_changeset(attrs) |> Repo.insert!()
  end

  # Releases are always deleted and recreated (never updated individually).
  # Use delete_releases_for_item + create_release! instead.

  def list_releases do
    all =
      from(r in Release,
        join: i in assoc(r, :item),
        where: i.status == :watching and r.in_library == false,
        order_by: [asc: r.air_date],
        preload: [:item]
      )
      |> Repo.all()

    upcoming = Enum.reject(all, & &1.released)
    released = Enum.filter(all, & &1.released)

    %{upcoming: upcoming, released: released}
  end

  @doc "Dismiss a single release by deleting it."
  def dismiss_release(release_id) do
    case Repo.get(Release, release_id) do
      nil ->
        {:error, :not_found}

      release ->
        result = Repo.delete(release)
        broadcast_releases_updated([release.item_id])
        result
    end
  end

  def list_releases_for_item(item_id) do
    from(r in Release, where: r.item_id == ^item_id, order_by: [asc: r.air_date])
    |> Repo.all()
  end

  def delete_releases_for_item(item_id) do
    from(r in Release, where: r.item_id == ^item_id) |> Repo.delete_all()
  end

  # --- Events ---

  def create_event(attrs) do
    Event.create_changeset(attrs) |> Repo.insert()
  end

  def create_event!(attrs) do
    Event.create_changeset(attrs) |> Repo.insert!()
  end

  def list_recent_events(limit \\ 20) do
    from(e in Event,
      order_by: [{:desc, e.inserted_at}, {:desc, fragment("rowid")}],
      limit: ^limit
    )
    |> Repo.all()
  end

  # --- Bulk operations ---

  @doc """
  Mark releases as in_library for a given item.

  TV series: episodes at or before last_library_season/episode are in the library.
  Movies: all releases with `released: true` are marked (the library entity existing
  means the collection is tracked, and released movies are available).
  """
  def mark_in_library_releases(%Item{media_type: :tv_series} = item) do
    season = item.last_library_season || 0
    episode = item.last_library_episode || 0

    if season > 0 do
      {count, _} =
        from(r in Release,
          where: r.item_id == ^item.id,
          where:
            r.season_number < ^season or
              (r.season_number == ^season and r.episode_number <= ^episode)
        )
        |> Repo.update_all(set: [in_library: true])

      if count > 0, do: broadcast_releases_updated([item.id])
    end
  end

  def mark_in_library_releases(%Item{media_type: :movie} = item) do
    {count, _} =
      from(r in Release,
        where: r.item_id == ^item.id and r.released == true
      )
      |> Repo.update_all(set: [in_library: true])

    if count > 0, do: broadcast_releases_updated([item.id])
  end

  def mark_past_releases_as_released do
    today = Date.utc_today()

    from(r in Release,
      where: not is_nil(r.air_date) and r.air_date <= ^today and r.released == false
    )
    |> Repo.update_all(set: [released: true])
  end
end
