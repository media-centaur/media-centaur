defmodule MediaCentaur.Pipeline.ImageRepair do
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

  Broadcasts `{:images_pending, %{entity_id, media_dir}}` on
  `Topics.pipeline_images/0`, deduped per `(entity_id, media_dir)` so one
  Producer wake-up handles every missing role for a given entity.
  """
  import Ecto.Query

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library.ImageCache
  alias MediaCentaur.ImageFiles
  alias MediaCentaur.Library.ImageHealth
  alias MediaCentaur.Pipeline.EntityImageContext
  alias MediaCentaur.Pipeline.ImageQueue
  alias MediaCentaur.Pipeline.ImageQueueEntry
  alias MediaCentaur.Repo
  alias MediaCentaur.TMDB
  alias MediaCentaur.Topics

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
      Log.info(:pipeline, "image_repair: starting — #{length(missing)} missing files")
      do_repair(missing)
    end
  end

  @doc """
  Re-fetches every `library_images` row of `role` that has a cached file,
  regardless of whether it's present on disk. Each image's stale `?w=`
  derivatives are purged (so they regenerate from the new master, reclaiming
  cache space), then the queue row is reset/rebuilt and the pipeline
  re-downloads it at the *current* resize spec.

  This is the artwork-resolution backfill: changing the resolution preset, or
  the maintenance button, re-fetches only the affected role (backdrops) so the
  on-disk masters match the new setting.
  """
  @spec refetch_role(String.t()) :: {:ok, result()}
  def refetch_role(role) do
    entries = ImageHealth.list_by_role(role)

    if entries == [] do
      {:ok, %{enqueued: 0, queue_reused: 0, queue_rebuilt: 0, skipped: 0}}
    else
      Log.info(:pipeline, "image_refetch: #{role} — #{length(entries)} images")
      purge_derivatives(entries)
      do_repair(entries)
    end
  end

  defp purge_derivatives(entries) do
    Enum.each(entries, fn %{image: image} ->
      case ImageCache.resolve_path(image.content_url) do
        nil -> :ok
        path -> ImageFiles.purge_derivatives_for(path)
      end
    end)
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
              broadcasts: MapSet.put(acc.broadcasts, {queue_row.entity_id, queue_row.media_dir})
            }

          {:ok, :rebuilt, queue_row} ->
            %{
              counts: bump(acc.counts, [:enqueued, :queue_rebuilt]),
              broadcasts: MapSet.put(acc.broadcasts, {queue_row.entity_id, queue_row.media_dir})
            }

          {:skip, _reason} ->
            %{acc | counts: bump(acc.counts, [:skipped])}
        end
      end)

    Enum.each(broadcasts, fn {entity_id, media_dir} ->
      Topics.publish(
        Topics.pipeline_images(),
        {:images_pending, %{entity_id: entity_id, media_dir: media_dir}}
      )
    end)

    Log.info(
      :pipeline,
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
    owner_id = image.owner_id

    case Repo.one(from(e in ImageQueueEntry, where: e.owner_id == ^owner_id and e.role == ^role)) do
      nil -> :missing
      entry -> {:ok, entry}
    end
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
    with {:ok, tmdb_context} <- EntityImageContext.find_tmdb_context(entity_id, entity_type),
         {:ok, media_dir} <- EntityImageContext.find_media_dir(entity_id, entity_type),
         {:ok, source_url, owner_id, broadcast_entity_id} <-
           derive_source_url(image, entity_id, entity_type, tmdb_context) do
      attrs = %{
        owner_id: owner_id,
        owner_type: to_string(entity_type),
        role: image.role,
        source_url: source_url,
        entity_id: broadcast_entity_id,
        media_dir: media_dir,
        status: "pending",
        retry_count: 0
      }

      case ImageQueue.create(attrs) do
        {:ok, entry} ->
          {:ok, :rebuilt, entry}

        {:error, reason} ->
          Log.warning(
            :pipeline,
            "image_repair: queue insert failed for #{owner_id}/#{image.role}: #{inspect(reason)}"
          )

          {:skip, :queue_insert_failed}
      end
    else
      {:skip, reason} ->
        Log.warning(
          :pipeline,
          "image_repair: skipping #{entity_type}:#{entity_id} (#{image.role}): #{inspect(reason)}"
        )

        {:skip, reason}
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
