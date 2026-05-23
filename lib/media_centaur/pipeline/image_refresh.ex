defmodule MediaCentaur.Pipeline.ImageRefresh do
  @moduledoc """
  Force re-fetch + re-enqueue *all* artwork for one entity from TMDB.

  Unlike `ImageRepair` (which rebuilds queue rows only for `Image`
  records whose files are missing), this reuses the **import** enqueue
  path: it derives the full artwork list straight from fresh TMDB
  metadata and broadcasts `{:enqueue_images, …}`. The image Producer
  creates/upserts queue rows and downloads; `Library.upsert_image/2`
  then replaces `content_url` on completion — so a refresh both fills a
  gap (no artwork at all) and replaces existing art.

  `enqueue_refresh/2` is the web entry point: it cheaply pre-checks that
  the entity is TMDB-identified, then schedules `ImageRefreshWorker`
  (Oban) so the work outlives the LiveView (ADR-049). `refresh_entity/2`
  is the synchronous core run by the worker.

  Scope: top-level entities shown in the detail → manage view —
  `:movie`, `:tv_series`, `:movie_series`, `:video_object`.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Pipeline.EntityImageContext
  alias MediaCentaur.Pipeline.ImageRefreshWorker
  alias MediaCentaur.TMDB
  alias MediaCentaur.TMDB.Mapper
  alias MediaCentaur.Topics

  @type entity_type :: :movie | :tv_series | :movie_series | :video_object

  @doc """
  Schedules a refresh for one entity. Returns `{:error, :no_tmdb_id}`
  (without enqueuing) when the entity is not TMDB-identified, else the
  `Oban.insert/1` result.
  """
  @spec enqueue_refresh(String.t(), entity_type()) ::
          {:ok, Oban.Job.t()} | {:error, :no_tmdb_id} | {:error, Ecto.Changeset.t()}
  def enqueue_refresh(entity_id, type) do
    case EntityImageContext.find_tmdb_context(entity_id, type) do
      {:ok, _tmdb} ->
        %{entity_id: entity_id, entity_type: to_string(type)}
        |> ImageRefreshWorker.new()
        |> Oban.insert()

      {:skip, _reason} ->
        {:error, :no_tmdb_id}
    end
  end

  @doc """
  Re-fetches TMDB metadata for one entity and broadcasts
  `{:enqueue_images, …}`. Returns `{:ok, count}` (artwork roles
  enqueued) or `{:error, reason}`.
  """
  @spec refresh_entity(String.t(), entity_type()) :: {:ok, non_neg_integer()} | {:error, term()}
  def refresh_entity(entity_id, type) do
    with {:ok, tmdb_id} <- EntityImageContext.find_tmdb_context(entity_id, type),
         {:ok, watch_dir} <- EntityImageContext.find_watch_dir(entity_id, type),
         {:ok, data} <- fetch_metadata(type, tmdb_id) do
      enqueue(entity_id, type, watch_dir, Mapper.image_list(data))
    else
      {:skip, reason} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp enqueue(entity_id, type, _watch_dir, []) do
    Log.info(:library, "image_refresh: no TMDB artwork for #{type}:#{entity_id}")
    {:ok, 0}
  end

  defp enqueue(entity_id, type, watch_dir, images) do
    pending =
      Enum.map(images, fn image ->
        %{
          owner_id: entity_id,
          owner_type: to_string(type),
          role: image.role,
          source_url: image.url,
          extension: image.extension
        }
      end)

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      Topics.pipeline_images(),
      {:enqueue_images, %{entity_id: entity_id, watch_dir: watch_dir, images: pending}}
    )

    Log.info(:library, "image_refresh: enqueued #{length(pending)} images for #{type}:#{entity_id}")
    {:ok, length(pending)}
  end

  defp fetch_metadata(:movie, tmdb_id), do: TMDB.Client.get_movie(tmdb_id)
  defp fetch_metadata(:video_object, tmdb_id), do: TMDB.Client.get_movie(tmdb_id)
  defp fetch_metadata(:tv_series, tmdb_id), do: TMDB.Client.get_tv(tmdb_id)
  defp fetch_metadata(:movie_series, tmdb_id), do: TMDB.Client.get_collection(tmdb_id)
end
