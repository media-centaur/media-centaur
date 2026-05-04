defmodule MediaCentarr.Pipeline.ImageRepair do
  @moduledoc """
  Rebuilds `pipeline_image_queue` rows for `library_images` whose files
  are absent on disk, then asks the pipeline to re-download them.

  Two recovery modes per missing image:

    * **Reuse** — a `pipeline_image_queue` row already exists for this
      `(owner_id, role)`. Reset it to `status: "pending"` with
      `retry_count: 0` and broadcast.

    * **Rebuild** — no queue row exists (legacy DBs, showcase pre-queue
      seeds). Walk the entity up to TMDB via the entity's `tmdb_id`
      column (movies, TV series, movie series, video objects). Episodes
      derive their TMDB id from the parent TV series. Fetch metadata,
      pull the `poster_path` / `backdrop_path` / `still_path` for the
      role, and insert a fresh queue row.

  Broadcasts `{:images_pending, %{entity_id, watch_dir}}` on
  `Topics.pipeline_images/0`, deduped per `(entity_id, watch_dir)` so one
  Producer wake-up handles every missing role for a given entity.
  """
  import Ecto.Query

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Library
  alias MediaCentarr.Library.Episode
  alias MediaCentarr.Library.ImageHealth
  alias MediaCentarr.Library.Season
  alias MediaCentarr.Library.WatchedFile
  alias MediaCentarr.Pipeline.ImageQueue
  alias MediaCentarr.Pipeline.ImageQueueEntry
  alias MediaCentarr.Repo
  alias MediaCentarr.TMDB
  alias MediaCentarr.Topics

  @tmdb_cdn "https://image.tmdb.org/t/p/original"

  @type result :: %{
          enqueued: non_neg_integer(),
          queue_reused: non_neg_integer(),
          queue_rebuilt: non_neg_integer(),
          skipped: non_neg_integer()
        }

  @spec repair_all() :: {:ok, result()}
  def repair_all do
    missing = ImageHealth.list_missing()

    if missing == [] do
      {:ok, %{enqueued: 0, queue_reused: 0, queue_rebuilt: 0, skipped: 0}}
    else
      Log.info(:library, "image_repair: starting — #{length(missing)} missing files")
      do_repair(missing)
    end
  end

  defp do_repair(missing) do
    initial = %{
      counts: %{enqueued: 0, queue_reused: 0, queue_rebuilt: 0, skipped: 0},
      broadcasts: MapSet.new()
    }

    %{counts: counts, broadcasts: broadcasts} =
      Enum.reduce(missing, initial, fn entry, acc ->
        case repair_one(entry) do
          {:ok, :reused, queue_row} ->
            %{
              counts: bump(acc.counts, [:enqueued, :queue_reused]),
              broadcasts: MapSet.put(acc.broadcasts, {queue_row.entity_id, queue_row.watch_dir})
            }

          {:ok, :rebuilt, queue_row} ->
            %{
              counts: bump(acc.counts, [:enqueued, :queue_rebuilt]),
              broadcasts: MapSet.put(acc.broadcasts, {queue_row.entity_id, queue_row.watch_dir})
            }

          {:skip, _reason} ->
            %{acc | counts: bump(acc.counts, [:skipped])}
        end
      end)

    Enum.each(broadcasts, fn {entity_id, watch_dir} ->
      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        Topics.pipeline_images(),
        {:images_pending, %{entity_id: entity_id, watch_dir: watch_dir}}
      )
    end)

    Log.info(
      :library,
      "image_repair: done — reused=#{counts.queue_reused} rebuilt=#{counts.queue_rebuilt} skipped=#{counts.skipped}"
    )

    {:ok, counts}
  end

  defp bump(counts, keys) do
    Enum.reduce(keys, counts, fn key, acc -> Map.update!(acc, key, &(&1 + 1)) end)
  end

  defp repair_one(%{image: image, entity_id: entity_id, entity_type: entity_type}) do
    case find_existing_queue_row(image.role, image) do
      {:ok, queue_row} -> reset_queue_row(queue_row)
      :missing -> rebuild_queue_row(image, entity_id, entity_type)
    end
  end

  defp find_existing_queue_row(role, image) do
    owner_id = owner_id_for(image)

    case Repo.one(from(e in ImageQueueEntry, where: e.owner_id == ^owner_id and e.role == ^role)) do
      nil -> :missing
      entry -> {:ok, entry}
    end
  end

  defp owner_id_for(image) do
    image.movie_id || image.episode_id || image.tv_series_id ||
      image.movie_series_id || image.video_object_id
  end

  defp reset_queue_row(%ImageQueueEntry{status: "pending", retry_count: 0} = entry) do
    {:ok, :reused, entry}
  end

  defp reset_queue_row(%ImageQueueEntry{} = entry) do
    {:ok, updated} =
      Repo.update(Ecto.Changeset.change(entry, status: "pending", retry_count: 0))

    {:ok, :reused, updated}
  end

  # -- rebuild path --------------------------------------------------------

  defp rebuild_queue_row(image, entity_id, entity_type) do
    with {:ok, tmdb_context} <- find_tmdb_context(entity_id, entity_type),
         {:ok, watch_dir} <- find_watch_dir(entity_id, entity_type),
         {:ok, source_url, owner_id, broadcast_entity_id} <-
           derive_source_url(image, entity_id, entity_type, tmdb_context) do
      attrs = %{
        owner_id: owner_id,
        owner_type: to_string(entity_type),
        role: image.role,
        source_url: source_url,
        entity_id: broadcast_entity_id,
        watch_dir: watch_dir,
        status: "pending",
        retry_count: 0
      }

      case ImageQueue.create(attrs) do
        {:ok, entry} ->
          {:ok, :rebuilt, entry}

        {:error, reason} ->
          Log.warning(
            :library,
            "image_repair: queue insert failed for #{owner_id}/#{image.role}: #{inspect(reason)}"
          )

          {:skip, :queue_insert_failed}
      end
    else
      {:skip, reason} ->
        Log.warning(
          :library,
          "image_repair: skipping #{entity_type}:#{entity_id} (#{image.role}): #{inspect(reason)}"
        )

        {:skip, reason}
    end
  end

  # -- tmdb lookup ---------------------------------------------------------
  # Returns {:ok, tmdb_id} for top-level entities, or
  # {:ok, {tmdb_id, season_number, episode_number, parent_tv_series_id}}
  # for episodes.

  defp find_tmdb_context(entity_id, :movie), do: tmdb_from_entity(Library.fetch_movie(entity_id))

  defp find_tmdb_context(entity_id, :tv_series), do: tmdb_from_entity(Library.fetch_tv_series(entity_id))

  defp find_tmdb_context(entity_id, :movie_series),
    do: tmdb_from_entity(Library.fetch_movie_series(entity_id))

  defp find_tmdb_context(entity_id, :video_object),
    do: tmdb_from_entity(Library.fetch_video_object(entity_id))

  defp find_tmdb_context(episode_id, :episode) do
    with {:ok, episode} <- Library.fetch_episode(episode_id),
         %Season{} = season <- Repo.get(Season, episode.season_id),
         {:ok, tmdb_id} <- find_tmdb_context(season.tv_series_id, :tv_series) do
      {:ok, {tmdb_id, season.season_number, episode.episode_number, season.tv_series_id}}
    else
      _ -> {:skip, :no_tmdb_id}
    end
  end

  defp tmdb_from_entity({:ok, %{tmdb_id: tmdb_id}}) when is_binary(tmdb_id) and tmdb_id != "",
    do: {:ok, tmdb_id}

  defp tmdb_from_entity(_), do: {:skip, :no_tmdb_id}

  defp fk_for(:movie), do: :movie_id
  defp fk_for(:tv_series), do: :tv_series_id
  defp fk_for(:movie_series), do: :movie_series_id
  defp fk_for(:video_object), do: :video_object_id

  # -- watch_dir lookup ----------------------------------------------------

  defp find_watch_dir(episode_id, :episode) do
    with {:ok, %Episode{} = episode} <- Library.fetch_episode(episode_id),
         %Season{} = season <- Repo.get(Season, episode.season_id) do
      find_watch_dir(season.tv_series_id, :tv_series)
    else
      _ -> {:skip, :no_watch_dir}
    end
  end

  defp find_watch_dir(entity_id, entity_type) do
    fk = fk_for(entity_type)

    case Repo.one(from(w in WatchedFile, where: field(w, ^fk) == ^entity_id, limit: 1)) do
      %WatchedFile{watch_dir: watch_dir} when is_binary(watch_dir) ->
        {:ok, watch_dir}

      _ ->
        {:skip, :no_watch_dir}
    end
  end

  # -- source-url derivation -----------------------------------------------

  defp derive_source_url(image, entity_id, :movie, tmdb_id) do
    resolve_via(TMDB.Client.get_movie(tmdb_id), image.role, entity_id, entity_id, image.role)
  end

  defp derive_source_url(image, entity_id, :tv_series, tmdb_id) do
    resolve_via(TMDB.Client.get_tv(tmdb_id), image.role, entity_id, entity_id, image.role)
  end

  defp derive_source_url(image, entity_id, :movie_series, tmdb_id) do
    resolve_via(TMDB.Client.get_collection(tmdb_id), image.role, entity_id, entity_id, image.role)
  end

  defp derive_source_url(image, entity_id, :video_object, tmdb_id) do
    resolve_via(TMDB.Client.get_movie(tmdb_id), image.role, entity_id, entity_id, image.role)
  end

  defp derive_source_url(
         _image,
         entity_id,
         :episode,
         {tmdb_id, season_number, episode_number, tv_series_id}
       ) do
    case TMDB.Client.get_season(tmdb_id, season_number) do
      {:ok, data} ->
        case find_episode_still(data, episode_number) do
          nil -> {:skip, {:tmdb_no_still, episode_number}}
          path -> {:ok, @tmdb_cdn <> path, entity_id, tv_series_id}
        end

      {:error, reason} ->
        {:skip, {:tmdb_error, reason}}
    end
  end

  defp resolve_via({:ok, data}, role, owner_id, entity_id, _role_log) do
    case role_path(data, role) do
      nil -> {:skip, {:tmdb_no_path, role}}
      path -> {:ok, @tmdb_cdn <> path, owner_id, entity_id}
    end
  end

  defp resolve_via({:error, reason}, _role, _owner_id, _entity_id, _role_log) do
    {:skip, {:tmdb_error, reason}}
  end

  defp role_path(data, "poster"), do: blank_to_nil(data["poster_path"])
  defp role_path(data, "backdrop"), do: blank_to_nil(data["backdrop_path"])
  defp role_path(_data, _other), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(path) when is_binary(path), do: path

  defp find_episode_still(data, episode_number) do
    (data["episodes"] || [])
    |> Enum.find(fn episode -> episode["episode_number"] == episode_number end)
    |> case do
      %{"still_path" => still} -> blank_to_nil(still)
      _ -> nil
    end
  end
end
