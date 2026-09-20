defmodule MediaCentaur.Maintenance do
  use Boundary,
    deps: [
      MediaCentaur.Library,
      MediaCentaur.Pipeline,
      MediaCentaur.Review,
      MediaCentaur.Subtitles,
      MediaCentaur.Watcher
    ]

  @moduledoc """
  Operator-run library maintenance — the actions behind Settings →
  Maintenance and Settings → Danger Zone: clear the database, rebuild or
  repair artwork, refresh subtitles and extra names. A title's TMDB
  facts are not repaired here: the library is a projection of the TMDB
  store (`MediaCentaur.Pipeline.TmdbProjection`, ADR-071).

  Each action orchestrates across contexts (Library rows, Review rows,
  image files on disk, the image queue), which is why it is owned here
  rather than in `Settings` — shared key/value infrastructure with no
  domain logic, see
  [ADR-029](../decisions/architecture/2026-03-26-029-data-decoupling.md).
  The unattended versions of the backfills run from
  `MediaCentaur.BootHeal`.
  """
  import Ecto.Query

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Settings.Config

  alias MediaCentaur.Library.ImageCache
  alias MediaCentaur.Repo
  alias MediaCentaur.Library
  alias MediaCentaur.Library.Image

  alias MediaCentaur.Library.{
    Movie,
    MovieSeries,
    TVSeries,
    VideoObject,
    WatchedFile
  }

  # --- Async variants (ADR-049) ---
  #
  # Each runs its (long, library-wide) counterpart on
  # a supervised context-layer task. These must outlive the triggering
  # LiveView — a navigated-away admin shouldn't abort a bulk refresh — so
  # they live here, not in a web-layer `start_child`. On completion each
  # sends a result message to `reply_to` for the UI to clear its in-flight
  # flag and show the result.

  @doc "Async `clear_database/0`; sends `:database_cleared` to `reply_to`."
  def clear_database_async(reply_to) do
    run_async(fn ->
      clear_database()
      send(reply_to, :database_cleared)
    end)
  end

  @doc "Async `refresh_image_cache/0`; sends `{:image_cache_refreshed, count}`."
  def refresh_image_cache_async(reply_to) do
    run_async(fn ->
      {:ok, count} = refresh_image_cache()
      send(reply_to, {:image_cache_refreshed, count})
    end)
  end

  @doc "Async `refresh_movie_subtitles/0`; sends `{:movie_subtitles_refreshed, result}`."
  def refresh_movie_subtitles_async(reply_to) do
    run_async(fn ->
      {:ok, result} = refresh_movie_subtitles()
      send(reply_to, {:movie_subtitles_refreshed, result})
    end)
  end

  @doc "Async `repair_missing_images/0`; sends `{:image_repair_complete, result}`."
  def repair_missing_images_async(reply_to) do
    run_async(fn ->
      {:ok, result} = repair_missing_images()
      send(reply_to, {:image_repair_complete, result})
    end)
  end

  @doc "Async `refetch_backdrops/0`; sends `{:backdrop_refetch_complete, result}`."
  def refetch_backdrops_async(reply_to) do
    run_async(fn ->
      {:ok, result} = refetch_backdrops()
      send(reply_to, {:backdrop_refetch_complete, result})
    end)
  end

  @doc "Async `rederive_extra_names/0`; sends `{:extra_names_rederived, result}`."
  def rederive_extra_names_async(reply_to) do
    run_async(fn ->
      {:ok, result} = rederive_extra_names()
      send(reply_to, {:extra_names_rederived, result})
    end)
  end

  defp run_async(fun) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fun)
    :ok
  end

  @doc """
  Destroys all records from every library resource in FK-safe order,
  then clears image files from disk.
  """
  def clear_database do
    MediaCentaur.Watcher.Supervisor.pause_during(fn ->
      Log.info(:library, "clearing database")
      entity_ids = collect_all_entity_ids()

      MediaCentaur.Review.clear_all()
      Library.EntityCascade.destroy_all!()

      media_dirs = Config.get(:media_dirs) || []

      Enum.each(media_dirs, fn dir ->
        clear_directory(ImageCache.dir_for(dir))
      end)

      Library.broadcast_entities_changed(entity_ids)

      Log.info(:library, "database cleared")
      :ok
    end)
  end

  @doc """
  Clears all cached artwork from disk, nulls out `content_url` on every
  Image record, then re-downloads images for all entities.

  Returns `{:ok, count}` where `count` is the number of entities processed.
  """
  def refresh_image_cache do
    Log.info(:library, "refreshing image cache")

    media_dirs = Config.get(:media_dirs) || []

    Enum.each(media_dirs, fn dir ->
      clear_directory(ImageCache.dir_for(dir))
    end)

    now = DateTime.utc_now()
    Repo.update_all(Image, set: [content_url: nil, updated_at: now])

    entities = collect_entities_with_images_and_files()

    Enum.each(entities, fn entity ->
      if media_dir = first_media_dir(entity) do
        MediaCentaur.Topics.publish(
          MediaCentaur.Topics.pipeline_images(),
          {:images_pending, %{entity_id: entity.id, media_dir: media_dir}}
        )
      end
    end)

    entity_ids = Enum.map(entities, & &1.id)
    Library.broadcast_entities_changed(entity_ids)

    Log.info(:library, "image cache refreshed — #{length(entities)} entities")
    {:ok, length(entities)}
  end

  @doc """
  Backfills subtitle tracks for movie files that have none yet —
  picks up libraries imported before subtitle detection shipped, or
  movies whose subs changed since import.

  Iterates only files linked to a movie (`movie_id` not nil) that
  currently have no persisted tracks in `subtitles_tracks`, calls
  `Subtitles.detect/1`, and persists the result via
  `Subtitles.replace_tracks_for_file/2`. Idempotent: subsequent runs
  skip files that already have tracks.

  Survives a missing `ffprobe` — only sidecars are detected in that
  case, exactly as during normal import.

  Returns `{:ok, %{updated: n, skipped: n}}`.
  """
  @spec refresh_movie_subtitles() ::
          {:ok, %{updated: non_neg_integer(), skipped: non_neg_integer()}}
  def refresh_movie_subtitles do
    Log.info(:library, "refreshing movie subtitles")

    files = movie_files_without_tracks()

    result = Enum.reduce(files, %{updated: 0, skipped: 0}, &process_subtitle_refresh/2)

    Log.info(
      :library,
      "movie subtitles refresh — #{result.updated} updated, #{result.skipped} skipped"
    )

    {:ok, result}
  end

  # Movie-linked WatchedFiles whose `subtitles_tracks` row count is
  # zero. The left-join + group_by keeps this a single SQL trip. After
  # Library Schema v2 Phase 2 Task B, WatchedFile reaches the Movie
  # through `PlayableItem(container_type: :movie)`.
  defp movie_files_without_tracks do
    Repo.all(
      from f in WatchedFile,
        join: pi in MediaCentaur.Library.PlayableItem,
        on: pi.id == f.playable_item_id and pi.container_type == :movie,
        left_join: t in MediaCentaur.Subtitles.Track,
        on: t.watched_file_id == f.id,
        group_by: f.id,
        having: count(t.id) == 0,
        select: f
    )
  end

  defp process_subtitle_refresh(%WatchedFile{file_path: path, id: id}, acc) do
    case MediaCentaur.Subtitles.detect(path) do
      [] ->
        Map.update!(acc, :skipped, &(&1 + 1))

      tracks ->
        case MediaCentaur.Subtitles.replace_tracks_for_file(id, tracks) do
          {:ok, _} -> Map.update!(acc, :updated, &(&1 + 1))
          {:error, _} -> Map.update!(acc, :skipped, &(&1 + 1))
        end
    end
  end

  @doc """
  Detects `library_images` rows whose files are absent on disk and
  re-queues each one into `pipeline_image_queue` so the pipeline can
  re-download. Uses the existing stored `source_url` when a queue row
  already exists, or re-queries TMDB to reconstruct one otherwise.

  Non-destructive — does not touch existing files on disk or image rows
  that are present. Returns the per-category counts from
  `MediaCentaur.Pipeline.ImageRepair.repair_all/0`.
  """
  @spec repair_missing_images() ::
          {:ok,
           %{
             enqueued: non_neg_integer(),
             queue_reused: non_neg_integer(),
             queue_rebuilt: non_neg_integer(),
             skipped: non_neg_integer()
           }}
  def repair_missing_images do
    MediaCentaur.Pipeline.ImageRepair.repair_all()
  end

  @doc """
  Re-fetches all backdrop artwork at the current resolution preset, purging
  stale `?w=` derivatives. The artwork-resolution backfill: triggered when the
  resolution setting changes, or manually from Library Maintenance, so existing
  backdrops on disk are re-downloaded to match the new setting.
  """
  @spec refetch_backdrops() ::
          {:ok,
           %{
             enqueued: non_neg_integer(),
             queue_reused: non_neg_integer(),
             queue_rebuilt: non_neg_integer(),
             skipped: non_neg_integer()
           }}
  def refetch_backdrops do
    MediaCentaur.Pipeline.ImageRepair.refetch_role("backdrop")
  end

  @doc """
  Returns a summary of image-health state — total rows, missing files
  count, and per-role breakdown. For the UI to display the repair button
  prominence.
  """
  @spec missing_images_summary() :: %{
          total: non_neg_integer(),
          missing: non_neg_integer(),
          by_role: %{String.t() => non_neg_integer()}
        }
  def missing_images_summary do
    MediaCentaur.Library.ImageHealth.summary()
  end

  @doc """
  Re-derives every extra's display name from its file path. Network-free and
  idempotent — heals records left wrong by an earlier parser-rule bug without a
  hand-written backfill ([ADR-057](../decisions/architecture/2026-06-14-057-derived-data-is-recomputable.md)).
  Delegates to `MediaCentaur.Pipeline.ExtraRederive.rederive_all/0`.
  """
  @spec rederive_extra_names() ::
          {:ok,
           %{
             scanned: non_neg_integer(),
             updated: non_neg_integer(),
             skipped: non_neg_integer()
           }}
  def rederive_extra_names do
    MediaCentaur.Pipeline.ExtraRederive.rederive_all()
  end

  @doc """
  Count of extras with a blank/missing name — the visible symptom the re-derive
  sweep repairs. For the UI to display the button's prominence.
  """
  @spec blank_extra_names_count() :: non_neg_integer()
  def blank_extra_names_count do
    MediaCentaur.Library.Extras.count_blank_names()
  end

  defp collect_all_entity_ids do
    Repo.all(from(t in TVSeries, select: t.id)) ++
      Repo.all(from(m in MovieSeries, select: m.id)) ++
      Repo.all(from(m in Movie, where: is_nil(m.movie_series_id), select: m.id)) ++
      Repo.all(from(v in VideoObject, select: v.id))
  end

  defp collect_entities_with_images_and_files do
    tv = Repo.preload(Repo.all(TVSeries), [:images, :watched_files])
    ms = Repo.preload(Repo.all(MovieSeries), [:images, :watched_files])

    standalone_movies =
      Repo.preload(Repo.all(from(m in Movie, where: is_nil(m.movie_series_id))), [
        :images,
        :watched_files
      ])

    vo = Repo.preload(Repo.all(VideoObject), [:images, :watched_files])

    tv ++ ms ++ standalone_movies ++ vo
  end

  defp first_media_dir(entity) do
    case entity.watched_files do
      [first | _] ->
        first.media_dir

      _ ->
        Log.warning(
          :library,
          "entity #{entity.id} has no watched files, skipping image operation"
        )

        nil
    end
  end

  defp clear_directory(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.each(entries, fn entry ->
          File.rm_rf!(Path.join(dir, entry))
        end)

      {:error, _} ->
        :ok
    end
  end
end
