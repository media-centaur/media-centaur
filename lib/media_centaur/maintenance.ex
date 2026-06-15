defmodule MediaCentaur.Maintenance do
  use Boundary,
    deps: [
      MediaCentaur.Library,
      MediaCentaur.Pipeline,
      MediaCentaur.Subtitles,
      MediaCentaur.TMDB,
      MediaCentaur.Watcher
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

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Repo
  alias MediaCentaur.Library
  alias MediaCentaur.Library.Image

  alias MediaCentaur.Library.{
    Episode,
    Extra,
    ExtraFile,
    ExtraProgress,
    ExternalId,
    ExternalIds,
    FilePresence,
    Movie,
    MovieSeries,
    PlayableItem,
    Season,
    TVSeries,
    VideoObject,
    WatchProgress,
    WatchedFile
  }

  alias MediaCentaur.Review.PendingFile
  alias MediaCentaur.TMDB.{Client, Mapper}

  # --- Async variants (ADR-049) ---
  #
  # Each runs its (long, library-wide, often TMDB-fetching) counterpart on
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

  @doc "Async `refresh_movie_credits/0`; sends `{:movie_credits_refreshed, result}`."
  def refresh_movie_credits_async(reply_to) do
    run_async(fn ->
      {:ok, result} = refresh_movie_credits()
      send(reply_to, {:movie_credits_refreshed, result})
    end)
  end

  @doc "Async `refresh_series_credits/0`; sends `{:series_credits_refreshed, result}`."
  def refresh_series_credits_async(reply_to) do
    run_async(fn ->
      {:ok, result} = refresh_series_credits()
      send(reply_to, {:series_credits_refreshed, result})
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

      Enum.each(resources_in_delete_order(), fn schema ->
        Repo.delete_all(schema)
      end)

      media_dirs = MediaCentaur.Config.get(:media_dirs) || []

      Enum.each(media_dirs, fn dir ->
        clear_directory(MediaCentaur.Config.images_dir_for(dir))
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

    media_dirs = MediaCentaur.Config.get(:media_dirs) || []

    Enum.each(media_dirs, fn dir ->
      clear_directory(MediaCentaur.Config.images_dir_for(dir))
    end)

    now = DateTime.utc_now()
    Repo.update_all(Image, set: [content_url: nil, updated_at: now])

    entities = collect_entities_with_images_and_files()

    Enum.each(entities, fn entity ->
      if media_dir = first_media_dir(entity) do
        Phoenix.PubSub.broadcast(
          MediaCentaur.PubSub,
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
  Backfills the `cast`, `crew`, and `imdb_id` fields on movies imported
  before those fields existed. Iterates movies with a non-nil `tmdb_id`,
  re-fetches TMDB metadata for any with empty `cast` *or* empty `crew`,
  and updates all three credit-related columns in place — no images,
  watch progress, or files are touched.

  Idempotent: subsequent runs skip movies that already have non-empty
  cast and non-empty crew. Rate-limited automatically by
  `MediaCentaur.TMDB.RateLimiter` inside `Client.get_movie/1`.

  Broadcasts `entities_changed` for the updated movies so the ETS
  Detail projection (and any open modal) picks up the new cast/crew
  instead of serving a stale, cast-less projection.

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
  `MediaCentaur.TMDB.RateLimiter` inside `Client.get_tv/1`.

  Broadcasts `entities_changed` for the updated series so dependent
  caches refresh in place.

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
  surface only. A future task will either (a) implement a
  `tmdb_fetched_at`-based skip predicate or (b) aggregate constituent-movie
  credits up to the collection level.
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
  # supplies the schema to iterate, the TMDB fetcher keyed by the
  # container's TMDB ExternalId row, and a builder that turns the
  # fetched body into update attrs. The schema's own
  # `update_credits_changeset/2` performs the write. The TMDB id and
  # any returned IMDB id ride on `library_external_ids` rather than
  # on the container column (Library Schema v2 Phase 1 Task 6).
  defp refresh_credits(%{label: label, schema: schema} = config) do
    Log.info(:library, "refreshing #{label} credits")

    records = records_with_tmdb_id(schema)
    initial = %{updated: 0, skipped: 0, failed: 0, updated_ids: []}

    result =
      Enum.reduce(records, initial, fn {record, tmdb_id}, acc ->
        process_credits_refresh(record, tmdb_id, acc, config)
      end)

    %{updated_ids: updated_ids} = result

    # The ETS-backed Detail projection (read by the modal via
    # `load_modal_entry/1`) rebuilds only on `{:entities_changed, _}`.
    # Without this broadcast the DB carries the fresh cast/crew but the
    # cached projection — and therefore the open modal — stays stale.
    Library.broadcast_entities_changed(updated_ids)

    counts = Map.delete(result, :updated_ids)

    Log.info(
      :library,
      "#{label} credits refresh — #{counts.updated} updated, #{counts.skipped} skipped, #{counts.failed} failed"
    )

    {:ok, counts}
  end

  # Returns `[{record, tmdb_id}, ...]` for every record of the schema
  # that has a TMDB ExternalId row attached. Source key depends on the
  # owner type: `tmdb_collection` for MovieSeries, `tmdb` for everything
  # else.
  defp records_with_tmdb_id(MovieSeries),
    do: records_with_tmdb_id(MovieSeries, "tmdb_collection", :movie_series)

  defp records_with_tmdb_id(Movie), do: records_with_tmdb_id(Movie, "tmdb", :movie)
  defp records_with_tmdb_id(TVSeries), do: records_with_tmdb_id(TVSeries, "tmdb", :tv_series)

  defp records_with_tmdb_id(schema, source, owner_type) do
    Repo.all(
      from(r in schema,
        join: e in ExternalId,
        on: e.owner_id == r.id and e.owner_type == ^owner_type,
        where: e.source == ^source,
        select: {r, e.external_id}
      )
    )
  end

  defp process_credits_refresh(%{cast: cast, crew: crew}, _tmdb_id, acc, _config)
       when cast != [] and crew != [] do
    Map.update!(acc, :skipped, &(&1 + 1))
  end

  defp process_credits_refresh(record, tmdb_id, acc, %{
         label: label,
         schema: schema,
         fetcher: fetcher,
         attrs_builder: attrs_builder
       }) do
    case fetcher.(tmdb_id) do
      {:ok, body} ->
        {credits_attrs, imdb_id} = attrs_builder.(body)

        record
        |> schema.update_credits_changeset(credits_attrs)
        |> Repo.update()
        |> case do
          {:ok, updated_record} ->
            _ = ExternalIds.put(:imdb, updated_record, imdb_id)

            acc
            |> Map.update!(:updated, &(&1 + 1))
            |> Map.update!(:updated_ids, &[updated_record.id | &1])

          {:error, _} ->
            Map.update!(acc, :failed, &(&1 + 1))
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
    {
      %{
        cast: Mapper.extract_cast(body["credits"]),
        crew: Mapper.extract_crew(body["credits"])
      },
      body["imdb_id"]
    }
  end

  defp build_series_credits_attrs(body) do
    {
      %{
        cast: Mapper.extract_cast(body["aggregate_credits"]),
        crew: Mapper.extract_creators(body["created_by"])
      },
      get_in(body, ["external_ids", "imdb_id"])
    }
  end

  # TMDB collection responses do not include `credits` at the collection
  # level — cast/crew only exist on the constituent `parts`. We honour
  # the contract anyway (empty lists are valid) so the maintenance entry
  # point stays uniform with movies/series. Aggregating from `parts`
  # would require N extra movie fetches and is out of scope here.
  defp build_movie_series_credits_attrs(_body) do
    {%{cast: [], crew: []}, nil}
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
    MediaCentaur.Library.count_blank_extra_names()
  end

  @doc """
  Boot-time auto-heal: runs the re-derive sweep in the background so a parser-rule
  improvement shipped in an update reaches existing records on the next restart,
  with no operator action. Network-free and idempotent, so running it on every
  boot is effectively a no-op unless a rule changed.

  Skipped under `:test` — the sweep writes to the DB, and a boot-spawned task runs
  outside the test's sandbox-owned process (an ownership error waiting to happen).
  Test coverage for the sweep itself lives in `ExtraRederiveTest`.
  """
  @spec heal_extra_names_on_boot(atom()) :: :skipped | :started
  def heal_extra_names_on_boot(:test), do: :skipped

  def heal_extra_names_on_boot(_env) do
    run_async(fn ->
      {:ok, summary} = rederive_extra_names()

      if summary.updated > 0 do
        Log.info(:library, "boot re-derive healed #{summary.updated} extra name(s)")
      end
    end)

    :started
  end

  @doc """
  Boot-time backfill: creates `ExtraFile` rows for extras imported before the
  ingest path wrote them (ExtraFile-unification / Schema v2 "Task G"), so they
  become "linked" and stop being re-emitted by `rescan_unlinked`. Network-free,
  idempotent. Skipped under `:test` (a boot-spawned task runs outside the
  sandbox-owned process); `Library.backfill_extra_files/0` is tested directly.
  """
  @spec backfill_extra_files_on_boot(atom()) :: :skipped | :started
  def backfill_extra_files_on_boot(:test), do: :skipped

  def backfill_extra_files_on_boot(_env) do
    run_async(fn ->
      %{created: created} = MediaCentaur.Library.backfill_extra_files()

      if created > 0 do
        Log.info(:library, "boot ExtraFile backfill linked #{created} extra file(s)")
      end
    end)

    :started
  end

  defp resources_in_delete_order do
    [
      PendingFile,
      ExtraProgress,
      WatchProgress,
      ExtraFile,
      Extra,
      Image,
      Episode,
      ExternalId,
      Movie,
      Season,
      WatchedFile,
      # FilePresence is the scan's skip-ledger (the watcher startup scan
      # skips any path already present here). The file rows above
      # (WatchedFile / ExtraFile) reference it by a plain column with no DB
      # cascade, so deleting them leaves orphaned presence rows that make a
      # post-clear rescan a no-op — the library can't be rebuilt from disk
      # without a reboot. Wipe it too so "Clear database" is a true reset.
      FilePresence,
      PlayableItem,
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
