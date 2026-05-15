defmodule MediaCentarr.Maintenance do
  use Boundary,
    deps: [
      MediaCentarr.Library,
      MediaCentarr.Pipeline,
      MediaCentarr.Subtitles,
      MediaCentarr.TMDB,
      MediaCentarr.Watcher
    ]

  @moduledoc """
  Operator-driven destructive operations — Settings → Danger Zone and the
  library-maintenance buttons. These actions intentionally cross context
  boundaries (purge Library schemas, clear image cache, repair missing
  images) so they are owned here rather than in `Settings`, which is
  defined as shared key/value infrastructure with no domain logic.

  See [ADR-029](../decisions/architecture/2026-03-26-029-data-decoupling.md):
  Settings is intentionally one-directional. Cross-context orchestration
  belongs in a dedicated context, not bolted onto a configuration store.
  """
  import Ecto.Query

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Repo
  alias MediaCentarr.Library
  alias MediaCentarr.Library.Image

  alias MediaCentarr.Library.{
    Episode,
    Extra,
    ExtraProgress,
    ExternalId,
    Movie,
    MovieSeries,
    Season,
    TVSeries,
    VideoObject,
    WatchProgress,
    WatchedFile
  }

  alias MediaCentarr.Review.PendingFile
  alias MediaCentarr.TMDB.{Client, Mapper}

  @doc """
  Destroys all records from every library resource in FK-safe order,
  then clears image files from disk.
  """
  def clear_database do
    MediaCentarr.Watcher.Supervisor.pause_during(fn ->
      Log.info(:library, "clearing database")
      entity_ids = collect_all_entity_ids()

      Enum.each(resources_in_delete_order(), fn schema ->
        Repo.delete_all(schema)
      end)

      watch_dirs = MediaCentarr.Config.get(:watch_dirs) || []

      Enum.each(watch_dirs, fn dir ->
        clear_directory(MediaCentarr.Config.images_dir_for(dir))
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

    watch_dirs = MediaCentarr.Config.get(:watch_dirs) || []

    Enum.each(watch_dirs, fn dir ->
      clear_directory(MediaCentarr.Config.images_dir_for(dir))
    end)

    now = DateTime.utc_now()
    Repo.update_all(Image, set: [content_url: nil, updated_at: now])

    entities = collect_entities_with_images_and_files()

    Enum.each(entities, fn entity ->
      if watch_dir = first_watch_dir(entity) do
        Phoenix.PubSub.broadcast(
          MediaCentarr.PubSub,
          MediaCentarr.Topics.pipeline_images(),
          {:images_pending, %{entity_id: entity.id, watch_dir: watch_dir}}
        )
      end
    end)

    entity_ids = Enum.map(entities, & &1.id)
    Library.broadcast_entities_changed(entity_ids)

    Log.info(:library, "image cache refreshed — #{length(entities)} entities")
    {:ok, length(entities)}
  end

  @doc """
  Backfills the `cast`, `crew`, and `imdb_id` fields on movies imported
  before those fields existed. Iterates movies with a non-nil `tmdb_id`,
  re-fetches TMDB metadata for any with empty `cast` *or* empty `crew`,
  and updates all three credit-related columns in place — no images,
  watch progress, or files are touched.

  Idempotent: subsequent runs skip movies that already have non-empty
  cast and non-empty crew. Rate-limited automatically by
  `MediaCentarr.TMDB.RateLimiter` inside `Client.get_movie/1`.

  Returns `{:ok, %{updated: n, skipped: n, failed: n}}`.
  """
  @spec refresh_movie_credits() ::
          {:ok, %{updated: non_neg_integer(), skipped: non_neg_integer(), failed: non_neg_integer()}}
  def refresh_movie_credits do
    refresh_credits(%{
      label: "movie",
      schema: Movie,
      fetcher: &Client.get_movie/1,
      attrs_builder: &build_movie_credits_attrs/1
    })
  end

  @doc """
  Backfills the `cast`, `crew` (creators), and `imdb_id` fields on TV
  series imported before those fields existed. Iterates series with a
  non-nil `tmdb_id`, re-fetches TMDB metadata for any with empty `cast`
  *or* empty `crew`, and updates all three credit-related columns in
  place — no images, watch progress, or files are touched.

  Idempotent: subsequent runs skip series that already have non-empty
  cast and non-empty crew. Rate-limited automatically by
  `MediaCentarr.TMDB.RateLimiter` inside `Client.get_tv/1`.

  Returns `{:ok, %{updated: n, skipped: n, failed: n}}`.
  """
  @spec refresh_series_credits() ::
          {:ok, %{updated: non_neg_integer(), skipped: non_neg_integer(), failed: non_neg_integer()}}
  def refresh_series_credits do
    refresh_credits(%{
      label: "series",
      schema: TVSeries,
      fetcher: &Client.get_tv/1,
      attrs_builder: &build_series_credits_attrs/1
    })
  end

  @doc """
  Refreshes cast/crew for every `MovieSeries` row from TMDB collection data.

  TMDB's `/collection/{id}` endpoint does not currently expose collection-
  level cast/crew. This function exists for schema-level symmetry with
  `refresh_movie_credits/0` and `refresh_series_credits/0` and to validate
  the third-caller shape of `refresh_credits/1`. With every payload
  returning `cast: [], crew: []`, the driver's `cast != [] and crew != []`
  skip clause never engages, so each run will re-attempt every collection
  — rate-limited by `TMDB.RateLimiter` but otherwise unbounded.

  **Not wired to a Settings button or scheduled job in this task.** API
  surface only. See campaign `library-schema-v2.md` follow-ups for the
  plan to either (a) implement a `tmdb_fetched_at`-based skip predicate
  or (b) aggregate constituent-movie credits up to the collection level.
  """
  @spec refresh_movie_series_credits() ::
          {:ok, %{updated: non_neg_integer(), skipped: non_neg_integer(), failed: non_neg_integer()}}
  def refresh_movie_series_credits do
    refresh_credits(%{
      label: "movie series",
      schema: MovieSeries,
      fetcher: &Client.get_collection/1,
      attrs_builder: &build_movie_series_credits_attrs/1
    })
  end

  # Shared driver for credit-refresh maintenance actions. Each caller
  # supplies the schema to iterate, the TMDB fetcher keyed by `tmdb_id`,
  # and a builder that turns the fetched body into update attrs. The
  # schema's own `update_credits_changeset/2` performs the write.
  defp refresh_credits(%{label: label, schema: schema} = config) do
    Log.info(:library, "refreshing #{label} credits")

    records = Repo.all(from r in schema, where: not is_nil(r.tmdb_id))

    result =
      Enum.reduce(records, %{updated: 0, skipped: 0, failed: 0}, fn record, acc ->
        process_credits_refresh(record, acc, config)
      end)

    Log.info(
      :library,
      "#{label} credits refresh — #{result.updated} updated, #{result.skipped} skipped, #{result.failed} failed"
    )

    {:ok, result}
  end

  defp process_credits_refresh(%{cast: cast, crew: crew}, acc, _config) when cast != [] and crew != [] do
    Map.update!(acc, :skipped, &(&1 + 1))
  end

  defp process_credits_refresh(record, acc, %{
         label: label,
         schema: schema,
         fetcher: fetcher,
         attrs_builder: attrs_builder
       }) do
    case fetcher.(record.tmdb_id) do
      {:ok, body} ->
        record
        |> schema.update_credits_changeset(attrs_builder.(body))
        |> Repo.update()
        |> case do
          {:ok, _} -> Map.update!(acc, :updated, &(&1 + 1))
          {:error, _} -> Map.update!(acc, :failed, &(&1 + 1))
        end

      {:error, reason} ->
        Log.warning(
          :library,
          "credits refresh failed for #{label} #{record.id}: #{inspect(reason)}"
        )

        Map.update!(acc, :failed, &(&1 + 1))
    end
  end

  defp build_movie_credits_attrs(body) do
    %{
      cast: Mapper.extract_cast(body["credits"]),
      crew: Mapper.extract_crew(body["credits"]),
      imdb_id: body["imdb_id"]
    }
  end

  defp build_series_credits_attrs(body) do
    %{
      cast: Mapper.extract_cast(body["aggregate_credits"]),
      crew: Mapper.extract_creators(body["created_by"]),
      imdb_id: get_in(body, ["external_ids", "imdb_id"])
    }
  end

  # TMDB collection responses do not include `credits` at the collection
  # level — cast/crew only exist on the constituent `parts`. We honour
  # the contract anyway (empty lists are valid) so the maintenance entry
  # point stays uniform with movies/series. Aggregating from `parts`
  # would require N extra movie fetches and is out of scope here.
  defp build_movie_series_credits_attrs(_body) do
    %{cast: [], crew: []}
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
  # zero. The left-join + group_by keeps this a single SQL trip.
  defp movie_files_without_tracks do
    Repo.all(
      from f in WatchedFile,
        left_join: t in MediaCentarr.Subtitles.Track,
        on: t.watched_file_id == f.id,
        where: not is_nil(f.movie_id),
        group_by: f.id,
        having: count(t.id) == 0,
        select: f
    )
  end

  defp process_subtitle_refresh(%WatchedFile{file_path: path, id: id}, acc) do
    case MediaCentarr.Subtitles.detect(path) do
      [] ->
        Map.update!(acc, :skipped, &(&1 + 1))

      tracks ->
        case MediaCentarr.Subtitles.replace_tracks_for_file(id, tracks) do
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
  `MediaCentarr.Pipeline.ImageRepair.repair_all/0`.
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
    MediaCentarr.Pipeline.ImageRepair.repair_all()
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
    MediaCentarr.Library.ImageHealth.summary()
  end

  defp resources_in_delete_order do
    [
      PendingFile,
      ExtraProgress,
      WatchProgress,
      Extra,
      Image,
      Episode,
      ExternalId,
      Movie,
      Season,
      WatchedFile,
      TVSeries,
      MovieSeries,
      VideoObject
    ]
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

  defp first_watch_dir(entity) do
    case entity.watched_files do
      [first | _] ->
        first.watch_dir

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
