defmodule MediaCentaur.Library.Inbound do
  @moduledoc """
  Subscribes to `"pipeline:publish"` and handles inbound events for the
  Library context.

  Handles one event type:

  - `{:entity_published, event}` — creates a type-specific record (TVSeries,
    MovieSeries, Movie, VideoObject), children, ExternalId, WatchedFile, queues
    images for download, and broadcasts `:entities_changed` — plus
    `Library.Events.MoviesAdded` when the file is a movie's first — then
    reports the file's link outcome (below)

  Existing entities are resolved by joining through `library_external_ids` —
  `MediaCentaur.Library.ExternalIds` is the sole source of truth for
  TMDB / IMDB ids (Library Schema v2 Phase 1 Task 6).

  ## Link outcome

  Every `{:entity_published, event}` ends in exactly one report of what
  became of its file, published by path on `Topics.library_file_events/0`:

    * `{:file_linked, file_path}` — the file is attached to its movie,
      episode, video or bonus feature (`Library.Files.linked?/1`).
    * `{:file_parked, file_path}` — the event asked for no link: the
      pipeline parked the file in the episode-mapping queue, which owns it
      from here.
    * `{:file_not_linked, %{file_path, media_dir, reason, match}}` —
      nothing is attached. `reason` is `{:ingest_failed, term}` or
      `:crashed`; `match` is the event's `%{tmdb_id, tmdb_type}`, the match
      the file was imported under.

  This is the only record of whether a file reached the library: the
  series of an unlinked episode exists but is hidden, so without the
  report an approval that linked nothing looked like one that worked.
  `Review` closes and reopens its items on it.

  ## PlayableItem invariant

  Every leaf row (Movie, Episode, VideoObject — and child Movies of a
  MovieSeries) is paired with a `Library.PlayableItem` at creation time
  (Library Schema v2 Phase 2 Task G). The PlayableItem is the canonical
  leaf the rest of the system writes against:

    * `Library.WatchedFile` keys to `playable_item_id` (Task B).
    * `Library.WatchProgress` keys to `playable_item_id` (Task C).

  Container rows above the leaf (`TVSeries`, `MovieSeries`) never carry a
  PlayableItem of their own — their PlayableItems hang off the child
  leaves created during `create_children`.

  ## Race-loss recovery

  Concurrent inserts of the same TMDB id no longer surface as a column-level
  unique-constraint violation on the container (the column is gone). The
  race is now detected at the `ExternalIds.put/3` call site after a
  successful container insert: if the put fails with the
  `(source, external_id, owner_fk)` unique index, the losing process looks
  up the winning ExternalId, deletes its orphaned container, and returns
  the winner. `EntityCascade.destroy!/1` drops the orphan container's
  PlayableItem alongside the row — the discriminator FK has no DB-level
  enforcement, so the cascade does it explicitly.
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Library
  alias MediaCentaur.Library.{ChangeLog, EntityCascade, ExternalIds, Helpers}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    MediaCentaur.Topics.subscribe(MediaCentaur.Topics.pipeline_publish())
    {:ok, %{}}
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Ingests a published entity event into the library.

  Creates a type-specific record (or links to an existing entity), children,
  ExternalId, and WatchedFile. Queues images for download and broadcasts
  `:entities_changed`.

  The event is a plain map with keys: `entity_type`, `entity_attrs`,
  `identifier`, `images`, `season`, `child_movie`, `extra`, `file_path`,
  `media_dir`.

  Returns `{:ok, entity, status, pending_images}` or `{:error, reason}`.
  Status is `:new`, `:new_child`, or `:existing`.
  """
  @spec ingest(map()) ::
          {:ok, map(), :new | :new_child | :existing, list()} | {:error, term()}
  def ingest(event) do
    arriving = arriving_movie(event)

    case create_or_link(event) do
      {:ok, entity, status, pending_images} ->
        link_file(entity, event)
        report_link_outcome(event)
        queue_images(entity, pending_images, event)
        Helpers.broadcast_entities_changed([entity.id])
        announce_arrival(arriving)

        Log.info(
          :library,
          "ingested #{event.entity_type} — #{Format.short_id(entity.id)} (#{status})"
        )

        # Populate the virtual `content_url` on the returned record from
        # the WatchedFile we just linked (Library Schema v2 Phase 2 Task I).
        # Callers — including the legacy Inbound contract that surfaces
        # `entity.content_url` — see the on-disk path without a reload.
        entity_with_url = reload_with_content_url(entity, event.entity_type)
        {:ok, entity_with_url, status, pending_images}

      {:error, reason} ->
        Log.warning(:library, "failed to ingest entity: #{inspect(reason)}")
        publish_not_linked(event, {:ingest_failed, reason})
        {:error, reason}
    end
  end

  defp report_link_outcome(%{parked: true, file_path: file_path}) do
    publish_link_outcome({:file_parked, file_path})
  end

  defp report_link_outcome(%{file_path: file_path} = event) do
    if Library.Files.linked?(file_path) do
      publish_link_outcome({:file_linked, file_path})
    else
      # Every leaf path links, and a series file without a position is
      # parked before it gets here (`Pipeline.Stages.FetchMetadata`), so an
      # ingest that linked nothing broke that invariant. It says so rather
      # than raising after its writes.
      publish_not_linked(event, {:ingest_failed, :no_link})
    end
  end

  defp publish_not_linked(%{file_path: file_path, media_dir: media_dir, match: match}, reason) do
    Log.warning(:library, "file not linked — #{inspect(reason)} (file=#{file_path})")

    publish_link_outcome(
      {:file_not_linked, %{file_path: file_path, media_dir: media_dir, reason: reason, match: match}}
    )
  end

  defp publish_link_outcome(message) do
    MediaCentaur.Topics.publish(MediaCentaur.Topics.library_file_events(), message)
  end

  defp reload_with_content_url(%Library.Movie{} = movie, :movie) do
    case Library.Containers.fetch(:movie, movie.id) do
      {:ok, reloaded} -> reloaded
      _ -> movie
    end
  end

  defp reload_with_content_url(%Library.VideoObject{} = video, :video_object) do
    case Library.Containers.fetch(:video_object, video.id) do
      {:ok, reloaded} -> reloaded
      _ -> video
    end
  end

  defp reload_with_content_url(entity, _type), do: entity

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  # `ingest/1` ends in a
  # SQLite write. They run **inline** in the GenServer, which serializes them
  # to exactly one writer at a time — which is precisely what SQLite's
  # single-writer model wants. The mailbox is the queue: under burst ingest
  # (a folder of images landing at once) messages wait in the mailbox instead
  # of becoming concurrent writers. `race_winner/2` still handles the rare
  # concurrent same-entity case via the unique constraint.
  #
  # This replaced an unbounded `Task.Supervisor.start_child`-per-event fan-out
  # whose rationale wrongly assumed "SQLite single-writer semantics serialize
  # the actual writes downstream." SQLite does not queue concurrent writers —
  # it rejects them with SQLITE_BUSY — so that fan-out manufactured contention
  # and produced a crash storm under burst on 2026-06-08 (busy_timeout +
  # bumped pool queue_timeouts across seven subsystems). Inlining removes the
  # contention at its source; `busy_timeout` (config :media_centaur, Repo) is
  # the belt-and-suspenders for any remaining concurrent writer (e.g. Oban).
  #
  # Inlining is safe here: `Inbound` has no `handle_call` and no synchronous
  # callers, so a busy mailbox is backpressure, never a caller timeout. If a
  # future throughput need appears, batch writes via a transaction rather than
  # reintroducing unbounded concurrency (see the FAN-OUT discussion).
  @impl true
  def handle_info({:entity_published, event}, state) do
    # A crash inside `ingest/1` skips its own outcome report, so the
    # boundary reports it: every published event ends in exactly one.
    with :crashed <- isolate("entity_published", fn -> ingest(event) end) do
      publish_not_linked(event, :crashed)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Per-event fault boundary for the inline write path. Inbound processes a
  # stream of independent events; one poison event must not crash the GenServer
  # and drop the rest of the mailbox (the fault isolation the old per-event task
  # fan-out provided incidentally). Expected failures are already handled inside
  # each function as `{:error, _}` tuples and logged there — this only catches
  # the unexpected, turning a raw `gen_server terminate` crash dump into a clean,
  # attributable `:library` error and letting the stream continue.
  defp isolate(label, fun) do
    fun.()
  rescue
    error ->
      Log.error(
        :library,
        "inbound #{label} failed: #{Exception.message(error)}"
      )

      :crashed
  catch
    kind, reason ->
      Log.error(:library, "inbound #{label} crashed: #{inspect({kind, reason})}")
      :crashed
  end

  # ---------------------------------------------------------------------------
  # Movie arrival
  # ---------------------------------------------------------------------------

  # A movie arrives when the library gains its first file of the movie
  # itself: the event carries a movie's own file (not a bonus feature),
  # and the library holds no file for that movie yet. Read before the
  # ingest writes, announced after it succeeds. A second copy, or a file
  # coming back from a remounted drive, is not an arrival: the library
  # already had a file for it.
  defp arriving_movie(%{extra: extra}) when not is_nil(extra), do: nil

  defp arriving_movie(event) do
    with tmdb_id when is_binary(tmdb_id) <- movie_tmdb_id(event),
         {id, ""} <- Integer.parse(tmdb_id),
         true <- movie_without_files?(tmdb_id) do
      id
    else
      _not_an_arrival -> nil
    end
  end

  defp movie_tmdb_id(%{entity_type: :movie, identifier: %{source: "tmdb", external_id: id}}), do: id
  defp movie_tmdb_id(%{entity_type: :movie_series, child_movie: %{attrs: %{tmdb_id: id}}}), do: id
  defp movie_tmdb_id(_event), do: nil

  defp movie_without_files?(tmdb_id) do
    case ExternalIds.find_by_external_id(:movie, tmdb_id) do
      nil -> true
      movie -> Library.Files.list_by_entity_id(movie.id) == []
    end
  end

  defp announce_arrival(nil), do: :ok

  defp announce_arrival(tmdb_id),
    do: Library.Events.broadcast(%Library.Events.MoviesAdded{tmdb_ids: [tmdb_id]})

  # ---------------------------------------------------------------------------
  # Entity creation / linking
  # ---------------------------------------------------------------------------

  defp create_or_link(event) do
    case find_existing_entity(event.identifier) do
      {:ok, entity} ->
        Log.info(:library, "found existing entity — #{Format.short_id(entity.id)}")
        link_to_existing(entity, event)

      :not_found ->
        Log.info(:library, "creating new entity")
        create_new(event)
    end
  end

  defp find_existing_entity(%{source: "tmdb_collection", external_id: value}) do
    case Library.ExternalIds.find_by_external_id(:movie_series, value) do
      nil -> :not_found
      entity -> {:ok, entity}
    end
  end

  defp find_existing_entity(%{source: _source, external_id: value}) do
    cond do
      tv = Library.ExternalIds.find_by_external_id(:tv_series, value) -> {:ok, tv}
      movie = Library.ExternalIds.find_by_external_id(:movie, value) -> {:ok, movie}
      vo = Library.ExternalIds.find_by_external_id(:video_object, value) -> {:ok, vo}
      true -> :not_found
    end
  end

  # ---------------------------------------------------------------------------
  # Create new type-specific record
  # ---------------------------------------------------------------------------

  defp create_new(event) do
    {entity_attrs, tmdb_id, imdb_id} = split_external_ids(event.entity_attrs)
    shared_id = Ecto.UUID.generate()

    case create_type_record(event.entity_type, entity_attrs, shared_id) do
      {:ok, type_record} ->
        # Pair every leaf container with its canonical PlayableItem
        # immediately. Library Schema v2 Phase 2 Task G: PlayableItem
        # is the canonical leaf, so it must exist alongside the
        # container regardless of whether a WatchedFile follows.
        # `:tv_series` and `:movie_series` are containers above the
        # leaf, not leaves themselves — their PlayableItems come from
        # `create_children` below (Episode / child Movie).
        maybe_ensure_self_playable_item!(type_record, event.entity_type)

        case put_external_ids(event, type_record, tmdb_id, imdb_id) do
          {:ok, type_record} ->
            owner_type = owner_type_for(event.entity_type)
            entity_images = collect_images(type_record.id, owner_type, event.images)

            case create_children(type_record, event) do
              {:ok, child_images} ->
                ChangeLog.record_addition(type_record, event.entity_type)
                {:ok, type_record, :new, entity_images ++ child_images}

              {:error, reason} ->
                {:error, reason}
            end

          {:race_lost, winner} ->
            Log.info(:library, "race lost — using winner #{Format.short_id(winner.id)}")
            # `EntityCascade.destroy!` drops the orphan container AND
            # its newly-attached PlayableItem (the discriminator FK has
            # no DB-level enforcement, so cascade must do it
            # explicitly). See `EntityCascade.delete_playable_items/2`.
            EntityCascade.destroy!(type_record.id)
            link_to_existing(winner, event)
        end

      {:error, _reason} = error ->
        error
    end
  end

  # PlayableItem-as-the-leaf-row pairing. For `:movie` / `:video_object`
  # the container row itself IS the leaf, so the PlayableItem points at
  # `type_record.id`. For `:tv_series` / `:movie_series` the leaf is a
  # child (Episode / child Movie); their PlayableItems are created
  # during `create_children`.
  defp maybe_ensure_self_playable_item!(%Library.Movie{id: id, position: position}, :movie) do
    ensure_playable_item!(:movie, id, position || 1)
  end

  defp maybe_ensure_self_playable_item!(%Library.VideoObject{id: id}, :video_object) do
    ensure_playable_item!(:video_object, id, 1)
  end

  defp maybe_ensure_self_playable_item!(_record, _type), do: :ok

  # Race-safe PlayableItem upsert at the `(container_type, container_id,
  # position)` triple. Delegates to `Library.PlayableItems.find_or_create/3`
  # — the canonical seam handles the unique-index race-loss case.
  defp ensure_playable_item!(container_type, container_id, position) do
    case Library.PlayableItems.find_or_create(container_type, container_id, position) do
      {:ok, %Library.PlayableItem{id: id}} -> id
      {:error, reason} -> raise "PlayableItem creation failed: #{inspect(reason)}"
    end
  end

  # Splits TMDB/IMDB ids out of the container attrs. The container columns
  # are gone; these ride on `library_external_ids` rows written after the
  # container insert.
  defp split_external_ids(entity_attrs) do
    tmdb_id = entity_attrs[:tmdb_id] || entity_attrs["tmdb_id"]
    imdb_id = entity_attrs[:imdb_id] || entity_attrs["imdb_id"]

    stripped = Map.drop(entity_attrs, [:tmdb_id, :imdb_id, "tmdb_id", "imdb_id"])

    {stripped, tmdb_id, imdb_id}
  end

  # Writes the TMDB / IMDB ExternalId rows for a freshly-inserted
  # container. The TMDB write is race-aware: if a concurrent ingest of
  # the same TMDB id won, our ExternalId insert hits the owner-FK-scoped
  # unique index *or* finds a winning row on another container. Look up
  # the winner and signal `:race_lost`; the caller cleans up the orphan
  # container so the loser doesn't leave a stale row behind.
  defp put_external_ids(event, type_record, tmdb_id, imdb_id) do
    case put_tmdb_id(event, type_record, tmdb_id) do
      :ok ->
        _ = ExternalIds.put(:imdb, type_record, imdb_id)
        {:ok, type_record}

      {:race_lost, winner} ->
        {:race_lost, winner}
    end
  end

  defp put_tmdb_id(_event, _type_record, nil), do: :ok

  defp put_tmdb_id(event, type_record, tmdb_id) when is_binary(tmdb_id) do
    source = tmdb_source_for(event.entity_type)

    case ExternalIds.put(source, type_record, tmdb_id) do
      {:ok, _row} ->
        :ok

      {:error, %Ecto.Changeset{}} ->
        # Either same `(source, external_id)` is already attached to this
        # container by a concurrent put (handled idempotently by `put/3`
        # itself), or it now attaches to a different winning container.
        # Resolve via cross-owner lookup.
        case find_winner(event.entity_type, tmdb_id) do
          nil ->
            Log.warning(
              :library,
              "race-loss: ExternalId conflict on (#{event.entity_type}, tmdb:#{tmdb_id}) but no owner found"
            )

            :ok

          %{id: same_id} when same_id == type_record.id ->
            :ok

          winner ->
            {:race_lost, winner}
        end
    end
  end

  defp find_winner(type, value) when type in [:tv_series, :movie_series, :movie, :video_object],
    do: Library.ExternalIds.find_by_external_id(type, value)

  defp tmdb_source_for(:movie_series), do: :tmdb_collection
  defp tmdb_source_for(_), do: :tmdb

  defp create_type_record(:tv_series, attrs, shared_id) do
    Library.Containers.create(:tv_series, Map.put(attrs, :id, shared_id))
  end

  defp create_type_record(:movie_series, attrs, shared_id) do
    Library.Containers.create(:movie_series, Map.put(attrs, :id, shared_id))
  end

  defp create_type_record(:movie, attrs, shared_id) do
    Library.Containers.create(:movie, Map.put(attrs, :id, shared_id))
  end

  defp create_type_record(:video_object, attrs, shared_id) do
    Library.Containers.create(:video_object, Map.put(attrs, :id, shared_id))
  end

  # Maps entity_type atom to the owner_type string used in image metadata
  defp owner_type_for(:tv_series), do: "tv_series"
  defp owner_type_for(:movie_series), do: "movie_series"
  defp owner_type_for(:movie), do: "movie"
  defp owner_type_for(:video_object), do: "video_object"

  # Maps entity_type atom to the FK key used in child records
  defp type_fk_for(:tv_series), do: :tv_series_id
  defp type_fk_for(:movie_series), do: :movie_series_id
  defp type_fk_for(:movie), do: :movie_id
  defp type_fk_for(:video_object), do: :video_object_id

  defp create_children(record, event) do
    entity_type = event.entity_type
    entity_id = record.id

    with {:ok, season_images} <- maybe_create_season(entity_type, entity_id, event),
         {:ok, movie_images} <- maybe_create_child_movie(entity_type, entity_id, event),
         :ok <- maybe_create_extra(entity_type, entity_id, event) do
      {:ok, season_images ++ movie_images}
    end
  end

  defp maybe_create_season(_entity_type, _entity_id, %{season: nil}), do: {:ok, []}

  defp maybe_create_season(entity_type, entity_id, %{season: season}) do
    create_season_and_episode(entity_type, entity_id, season)
  end

  defp maybe_create_child_movie(_entity_type, _entity_id, %{child_movie: nil}), do: {:ok, []}

  defp maybe_create_child_movie(entity_type, entity_id, %{child_movie: child_movie}) do
    case create_child_movie(entity_type, entity_id, child_movie) do
      {:ok, _movie, images} -> {:ok, images}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_create_extra(_entity_type, _entity_id, %{extra: nil}), do: :ok

  defp maybe_create_extra(entity_type, entity_id, %{extra: extra} = event) do
    create_extra(entity_type, entity_id, extra, event.media_dir)
  end

  # ---------------------------------------------------------------------------
  # Link to existing entity
  # ---------------------------------------------------------------------------

  defp link_to_existing(entity, event) do
    do_link_to_existing(entity, event)
  end

  # Extra on existing entity — always handled first (regardless of entity type)
  defp do_link_to_existing(entity, %{extra: %{} = extra} = event) do
    entity_type = event.entity_type

    season_images =
      if event.season do
        case create_season_and_episode(entity_type, entity.id, event.season) do
          {:ok, images} -> images
          {:error, _} -> []
        end
      else
        []
      end

    with :ok <- create_extra(entity_type, entity.id, extra, event.media_dir) do
      {:ok, entity, :existing, season_images}
    end
  end

  # TV series — ensure season + episode
  defp do_link_to_existing(entity, %{entity_type: :tv_series} = event) do
    if event.season do
      case create_season_and_episode(:tv_series, entity.id, event.season) do
        {:ok, images} -> {:ok, entity, :existing, images}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, entity, :existing, []}
    end
  end

  # Movie series — ensure child movie -> :new_child
  defp do_link_to_existing(entity, %{entity_type: :movie_series} = event) do
    backfill_images = backfill_collection_images(entity, event)

    if event.child_movie do
      case create_child_movie(:movie_series, entity.id, event.child_movie) do
        {:ok, _movie, images} -> {:ok, entity, :new_child, backfill_images ++ images}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, entity, :existing, backfill_images}
    end
  end

  # Standalone movie or video object — nothing to update on the entity
  # itself for content_url anymore (Library Schema v2 Phase 2 Task I
  # dropped the column). The file linkage happens downstream in
  # `link_file/2` via the PlayableItem / WatchedFile chain.
  defp do_link_to_existing(entity, _event), do: {:ok, entity, :existing, []}

  # A collection's own artwork is queued only at creation time. If that
  # queue was lost — a transient `get_collection` failure, or a MovieSeries
  # minted by an older build — subsequent movies of the same collection
  # never recovered it, leaving the collection backdrop-less forever.
  #
  # `event.images` carries the freshly-fetched collection artwork from THIS
  # import, so we self-heal here: re-queue only the roles the container is
  # still missing (idempotent — no redundant re-download of art already on
  # disk). When this import's own `get_collection` also failed, `event.images`
  # is empty and there's nothing to backfill; image-repair remains the
  # fallback (the hardened error branch now writes the tmdb id it needs).
  defp backfill_collection_images(entity, %{images: images}) when is_list(images) do
    existing_roles =
      :movie_series
      |> Library.Images.list_for_owner(entity.id)
      |> MapSet.new(& &1.role)

    images
    |> Enum.reject(&MapSet.member?(existing_roles, &1.role))
    |> then(&collect_images(entity.id, "movie_series", &1))
  end

  defp backfill_collection_images(_entity, _event), do: []

  # ---------------------------------------------------------------------------
  # Season + Episode
  # ---------------------------------------------------------------------------

  defp create_season_and_episode(entity_type, entity_id, season_data) do
    season_attrs =
      put_type_fk(
        %{
          season_number: season_data.season_number,
          name: season_data.name,
          episode_list: season_data.episode_list
        },
        entity_type,
        entity_id
      )

    with {:ok, season} <- find_or_create_season(entity_type, season_attrs) do
      Log.info(
        :library,
        "created season S#{season_data.season_number} — entity #{Format.short_id(entity_id)}"
      )

      if season_data[:episode] do
        create_episode(season, season_data.episode)
      else
        {:ok, []}
      end
    end
  end

  defp find_or_create_season(:tv_series, attrs) do
    Library.Seasons.find_or_create(attrs)
  end

  defp find_or_create_season(_entity_type, attrs) do
    # Non-TV-series types create seasons directly (rare case — extras with season context)
    Library.Seasons.create(attrs)
  end

  defp create_episode(season, episode_data) do
    episode_attrs = Map.put(episode_data.attrs, :season_id, season.id)

    case Library.Episodes.find_or_create(episode_attrs) do
      {:ok, episode} ->
        # Library Schema v2 Phase 2 Task G — Episode is a leaf, so pair
        # it with its PlayableItem at the `episode_number` position. The
        # file path lives on the WatchedFile linked to this leaf, not
        # on the Episode row itself (Phase 2 Task I).
        ensure_playable_item!(:episode, episode.id, episode.episode_number || 1)
        images = collect_images(episode.id, "episode", episode_data[:images] || [])
        {:ok, images}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Child Movie (for collections)
  # ---------------------------------------------------------------------------

  defp create_child_movie(entity_type, entity_id, child_movie_data) do
    movie_attrs =
      maybe_put(child_movie_data.attrs, :movie_series_id, entity_id, entity_type == :movie_series)

    result = Library.Containers.find_or_create_movie_for_series(movie_attrs)

    case result do
      {:ok, movie} ->
        # Library Schema v2 Phase 2 Task G — the child Movie is a leaf,
        # so pair it with its PlayableItem at its `position`
        # (collection ordering) — defaulting to 1 when missing. The file
        # path is recorded on the WatchedFile linked to this leaf, not
        # on the Movie row itself (Phase 2 Task I).
        ensure_playable_item!(:movie, movie.id, movie.position || 1)
        images = collect_images(movie.id, "movie", child_movie_data[:images] || [])
        {:ok, movie, images}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Extra
  # ---------------------------------------------------------------------------

  defp create_extra(entity_type, entity_id, extra_data, media_dir) do
    season =
      if extra_data.season_number do
        season_attrs =
          put_type_fk(
            %{
              season_number: extra_data.season_number,
              name: "Season #{extra_data.season_number}",
              episode_list: []
            },
            entity_type,
            entity_id
          )

        case find_or_create_season(entity_type, season_attrs) do
          {:ok, season} -> season
          _ -> nil
        end
      end

    # If the extra has a season_number, the Extra's owner is the Season,
    # not the parent container — extras live "alongside" the Season they
    # belong to.
    {owner_type, owner_id} =
      if season do
        {:season, season.id}
      else
        {entity_type, entity_id}
      end

    extra_attrs = %{
      name: extra_data.name,
      content_url: extra_data.content_url,
      position: 0,
      owner_type: owner_type,
      owner_id: owner_id
    }

    with {:ok, extra} <- Library.Extras.find_or_create_by_owner(extra_attrs) do
      link_extra_file(extra, media_dir)
    end
  end

  # Mirrors `link_file/2`'s WatchedFile write, for the bonus-features path: an
  # `ExtraFile` row makes the extra's file visible to `Discovery.already_linked?/1`
  # so it is not re-emitted and re-searched on every rescan, and gives
  # relink-on-move a row to re-point when the file moves.
  defp link_extra_file(%Library.Extra{content_url: nil}, _media_dir), do: :ok

  defp link_extra_file(%Library.Extra{} = extra, media_dir) do
    case Library.Files.create_extra(%{
           file_path: extra.content_url,
           media_dir: media_dir,
           extra_id: extra.id
         }) do
      {:ok, _extra_file} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Images — collect pending image metadata (no DB inserts)
  # ---------------------------------------------------------------------------

  defp collect_images(_owner_id, _owner_type, []), do: []

  defp collect_images(owner_id, owner_type, images) do
    Enum.map(images, fn image ->
      %{
        owner_id: owner_id,
        owner_type: owner_type,
        role: image.role,
        source_url: image.url,
        extension: output_extension(image.role)
      }
    end)
  end

  defp output_extension("logo"), do: "png"
  defp output_extension(_role), do: "jpg"

  # ---------------------------------------------------------------------------
  # Post-ingest: file linking and image queuing
  # ---------------------------------------------------------------------------

  defp link_file(entity, event) do
    case leaf_playable_item_id_for(entity, event) do
      nil ->
        # No leaf to attach this WatchedFile to: a bonus feature (linked
        # as an ExtraFile by `create_or_link/1`) or a file parked for
        # episode mapping. `report_link_outcome/1` says which.
        nil

      playable_item_id when is_binary(playable_item_id) ->
        attrs = %{
          file_path: event.file_path,
          media_dir: event.media_dir,
          playable_item_id: playable_item_id
        }

        watched_file = Library.Files.link!(attrs)

        # Persist detected subtitle tracks against the freshly-linked
        # file. The Subtitles context owns its own table; we hand it
        # the FK and the detector output.
        detected = MediaCentaur.Subtitles.detect(event.file_path)

        case MediaCentaur.Subtitles.replace_tracks_for_file(watched_file.id, detected) do
          {:ok, _tracks} ->
            :ok

          {:error, reason} ->
            Log.warning(
              :library,
              "subtitle persist failed for watched_file #{watched_file.id}: #{inspect(reason)}"
            )
        end

        watched_file
    end
  end

  # Resolves the leaf PlayableItem id for an event so `link_file/2` can
  # wire the WatchedFile to it. After Library Schema v2 Phase 2 Task G
  # the PlayableItem is created alongside the leaf container, so this
  # lookup is normally a find — `Library.PlayableItems.find_or_create/3`
  # remains the seam for the rare case where the leaf row predates
  # Task G (legacy data, factories that bypass Inbound).
  defp leaf_playable_item_id_for(entity, event) do
    case leaf_container_for(entity, event) do
      nil ->
        nil

      {container_type, container_id, position} ->
        ensure_playable_item!(container_type, container_id, position)
    end
  end

  # Returns `{container_type, container_id, position}` for the leaf
  # PlayableItem that owns this event's file. The leaf is the Movie /
  # Episode / VideoObject — never the TVSeries or MovieSeries (those
  # are containers above the leaf and never own a WatchedFile in the
  # new schema).
  #
  # An event carrying an `:extra` payload is the bonus-features path —
  # the file is the Extra's content, not the container's. Skip the
  # link_file step entirely; the Extra row carries the path on its own
  # `content_url` column (Phase 1 preserved it for Extras) so the file
  # is still reachable via the Extra → ExtraFile chain.
  defp leaf_container_for(_entity, %{extra: extra}) when not is_nil(extra), do: nil

  defp leaf_container_for(_entity, %{
         entity_type: :movie_series,
         child_movie: %{attrs: %{tmdb_id: child_tmdb_id}}
       })
       when is_binary(child_tmdb_id) do
    %{id: id, position: position} = Library.ExternalIds.find_by_external_id(:movie, child_tmdb_id)
    {:movie, id, position || 1}
  end

  defp leaf_container_for(entity, %{
         entity_type: :tv_series,
         season: %{season_number: season_number, episode: %{attrs: %{episode_number: episode_number}}}
       })
       when is_integer(season_number) and is_integer(episode_number) do
    # The Episode row was created earlier in the ingest pipeline (see
    # `maybe_create_season → create_episode`). After Library Schema v2
    # Phase 2 Task I the `Episode.content_url` column is gone — the
    # unambiguous key is `(tv_series_id, season_number, episode_number)`,
    # which the event already carries on its season + episode payload.
    case Library.Episodes.find_by_season_episode(entity.id, season_number, episode_number) do
      nil -> nil
      episode -> {:episode, episode.id, episode.episode_number || 1}
    end
  end

  defp leaf_container_for(_entity, %{entity_type: :tv_series}), do: nil

  defp leaf_container_for(entity, %{entity_type: :movie}), do: {:movie, entity.id, entity.position || 1}

  defp leaf_container_for(entity, %{entity_type: :video_object}), do: {:video_object, entity.id, 1}

  defp leaf_container_for(_entity, _event), do: nil

  defp queue_images(_entity, [], _event), do: :ok

  defp queue_images(entity, pending_images, event) do
    MediaCentaur.Topics.publish(
      MediaCentaur.Topics.pipeline_images(),
      {:enqueue_images, %{entity_id: entity.id, media_dir: event.media_dir, images: pending_images}}
    )
  end

  # ---------------------------------------------------------------------------
  # Type FK helpers
  # ---------------------------------------------------------------------------

  # Adds the type-specific FK to attrs.
  defp put_type_fk(attrs, entity_type, entity_id) do
    Map.put(attrs, type_fk_for(entity_type), entity_id)
  end

  # Conditionally puts a key-value pair into a map.
  defp maybe_put(map, _key, _value, false), do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)

  # ---------------------------------------------------------------------------
end
