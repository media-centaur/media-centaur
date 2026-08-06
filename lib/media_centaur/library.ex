defmodule MediaCentaur.Library do
  use Boundary,
    deps: [MediaCentaur.Retention, MediaCentaur.Subtitles],
    exports: [
      AbsenceSweeper,
      Availability,
      Browser,
      Containers,
      ContentUrls,
      EntityShape,
      Episode,
      EpisodeList,
      Episodes,
      Events,
      Events.EntitiesChanged,
      ExternalId,
      ExternalIds,
      Extra,
      ExtraFile,
      Extras,
      FileEventHandler,
      FilePresence,
      Files,
      Image,
      ImageHealth,
      Images,
      MediaInfo,
      MediaTrackOverride,
      MediaTrackOverrides,
      Movie,
      MovieList,
      MovieSeries,
      OwnerRef,
      Person,
      PlayableItem,
      PlayableItems,
      Posters,
      Progress,
      Progress.Events,
      Progress.Events.ProgressFlushed,
      Progress.Events.ProgressHydrated,
      Progress.Events.ProgressTicked,
      Progress.Worker,
      ProgressRecords,
      ProgressSummary,
      Relink,
      Season,
      Seasons,
      TVSeries,
      TypeResolver,
      VideoObject,
      Views,
      Views.BrowseItem,
      Views.ContinueWatching,
      Views.ContinueWatchingItem,
      Views.Detail,
      Views.DetailItem,
      Views.DetailItem.WatchedFile,
      Views.HeroCandidates,
      Views.HeroCandidatesItem,
      Views.RecentlyAdded,
      Views.RecentlyAddedItem,
      WatchedFile,
      Writes
    ]

  @moduledoc """
  The media library context — entities, images, external IDs, seasons, episodes,
  and watched files that flow through the ingestion pipeline.
  """
  import Ecto.Query

  alias MediaCentaur.Repo

  alias MediaCentaur.Topics

  alias MediaCentaur.Library.{
    ChangeEntry,
    Episode,
    ExternalId,
    HomeFeed,
    Image,
    MediaTrackOverrides,
    Movie,
    MovieSeries,
    OwnerRef,
    PlayableItem,
    PresentableQueries,
    ProgressRecords,
    Season,
    TVSeries,
    VideoObject,
    WatchedFile
  }

  @doc "Subscribe the caller to library entity change events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.library_updates())
  end

  # ---------------------------------------------------------------------------
  # Search-index source
  # ---------------------------------------------------------------------------

  @doc """
  Returns the lightweight catalogue used by `Library.Views.Search` to
  rebuild its in-memory index.

  Unlike `Library.Browser.fetch_all_typed_entries/0`, this source is
  **presence-agnostic** — entities are included regardless of whether
  their backing files are currently reachable. Presence is computed
  per-entity by the Search projection (`Library.presentable_entity_ids/0`)
  so the `:present_only` filter does real work instead of being a
  tautology (Phase 3 Task C follow-up I-1).

  ## Hoist rule

  The same singleton-collection hoist Browser applies, but using the
  `_by_record_count` variants so categorisation is stable across file
  presence changes. A `MovieSeries` with one child Movie record is
  hoisted (the child surfaces in place of the collection); two or more
  child records surface as a collection container.

  ## Shape

  A list of maps with exactly the fields the Search projection consumes:

      %{
        id: container_id,
        type: :movie | :tv_series | :movie_series | :video_object,
        name: String.t() | nil,
        date_published: Date.t() | nil,
        # only populated for container types that walk into children:
        episode_ids: [Episode.id()] | nil,   # ordered (season_number, episode_number)
        movie_ids: [Movie.id()] | nil        # ordered (position, id)
      }

  Returns at most ~5 queries (one per kind), independent of library size.
  """
  @spec list_all_entities_for_search() :: [map()]
  def list_all_entities_for_search do
    list_search_standalone_movies() ++
      list_search_hoisted_movies() ++
      list_search_tv_series() ++
      list_search_movie_series() ++
      list_search_video_objects()
  end

  defp list_search_standalone_movies do
    from(m in PresentableQueries.standalone_movies_by_record_count(),
      select: %{id: m.id, name: m.name, date_published: m.date_published}
    )
    |> Repo.all()
    |> Enum.map(&Map.merge(&1, %{type: :movie, episode_ids: nil, movie_ids: nil}))
  end

  defp list_search_hoisted_movies do
    from(m in PresentableQueries.singleton_collection_movies_by_record_count(),
      select: %{id: m.id, name: m.name, date_published: m.date_published}
    )
    |> Repo.all()
    |> Enum.map(&Map.merge(&1, %{type: :movie, episode_ids: nil, movie_ids: nil}))
  end

  defp list_search_tv_series do
    # TVSeries: presence-agnostic source, with each series' episode IDs
    # walked in canonical play order. TVSeries has no `date_published`
    # column, so we resolve to nil. Two queries: the series, then a
    # bulk episode lookup keyed by `tv_series_id`.
    series_records =
      Repo.all(from(t in TVSeries, select: %{id: t.id, name: t.name}))

    series_ids = Enum.map(series_records, & &1.id)

    episodes_by_series =
      from(e in Episode,
        join: s in Season,
        on: s.id == e.season_id,
        where: s.tv_series_id in ^series_ids,
        order_by: [asc: s.tv_series_id, asc: s.season_number, asc: e.episode_number],
        select: {s.tv_series_id, e.id}
      )
      |> Repo.all()
      |> Enum.group_by(fn {tv_id, _ep_id} -> tv_id end, fn {_tv_id, ep_id} -> ep_id end)

    Enum.map(series_records, fn %{id: tv_id, name: name} ->
      %{
        id: tv_id,
        type: :tv_series,
        name: name,
        date_published: nil,
        episode_ids: Map.get(episodes_by_series, tv_id, []),
        movie_ids: nil
      }
    end)
  end

  defp list_search_movie_series do
    # MovieSeries: presence-agnostic source with the same `_by_record_count`
    # hoist rule Browser uses. Two queries: the series (with name +
    # date_published), then a bulk child-movie lookup keyed by
    # `movie_series_id`.
    series_records =
      Repo.all(
        from([ms] in PresentableQueries.multi_child_movie_series_by_record_count(),
          select: %{id: ms.id, name: ms.name, date_published: ms.date_published}
        )
      )

    series_ids = Enum.map(series_records, & &1.id)

    movies_by_series =
      from(m in Movie,
        where: m.movie_series_id in ^series_ids,
        order_by: [asc: m.movie_series_id, asc: m.position, asc: m.id],
        select: {m.movie_series_id, m.id}
      )
      |> Repo.all()
      |> Enum.group_by(fn {ms_id, _m_id} -> ms_id end, fn {_ms_id, m_id} -> m_id end)

    Enum.map(series_records, fn %{id: ms_id, name: name, date_published: date_published} ->
      %{
        id: ms_id,
        type: :movie_series,
        name: name,
        date_published: date_published,
        episode_ids: nil,
        movie_ids: Map.get(movies_by_series, ms_id, [])
      }
    end)
  end

  defp list_search_video_objects do
    from(v in VideoObject,
      select: %{id: v.id, name: v.name, date_published: v.date_published}
    )
    |> Repo.all()
    |> Enum.map(&Map.merge(&1, %{type: :video_object, episode_ids: nil, movie_ids: nil}))
  end

  @doc """
  Returns the set of `(container_type, container_id)` pairs that have at
  least one currently-present `WatchedFile`. Used by `Library.Views.Search`
  to mark `present?` per row at refresh time.

  Issues one bulk query through `library_playable_items →
  library_watched_files`; presence is structurally implied by the
  Phase-3 FK on `WatchedFile.file_presence_id` (cascade-delete from
  `Library.FilePresence`). For TVSeries / MovieSeries presence, the
  `container_type` is `:episode` / `:movie` — the Search projection
  rolls presence up to the container by membership in the precomputed
  `episode_ids` / `movie_ids` it already holds.

  Result shape: `MapSet.new([{:movie, uuid}, {:episode, uuid}, ...])`.
  """
  @spec presentable_entity_ids() :: MapSet.t({atom(), Ecto.UUID.t()})
  def presentable_entity_ids do
    query =
      from(pi in PlayableItem,
        join: wf in WatchedFile,
        on: wf.playable_item_id == pi.id,
        distinct: true,
        select: {pi.container_type, pi.container_id}
      )

    MapSet.new(Repo.all(query))
  end

  @doc """
  Bulk variant of "the canonical PlayableItem id per container". Takes a
  list of `{container_type, container_id}` pairs and returns
  `%{ {container_type, container_id} => playable_item_id }`. Containers
  with multiple PlayableItems resolve to the lowest-position one.

  Issues at most one query per distinct `container_type` in the input
  (so ≤ 3 queries total: `:movie`, `:episode`, `:video_object`).
  Containers absent from the result have no PlayableItem.
  """
  @spec representative_playable_item_ids_by_container([{atom(), Ecto.UUID.t()}]) ::
          %{{atom(), Ecto.UUID.t()} => Ecto.UUID.t()}
  def representative_playable_item_ids_by_container([]), do: %{}

  def representative_playable_item_ids_by_container(pairs) when is_list(pairs) do
    pairs
    |> Enum.group_by(fn {type, _id} -> type end, fn {_type, id} -> id end)
    |> Enum.flat_map(fn {type, ids} ->
      ids = Enum.uniq(ids)

      from(p in PlayableItem,
        where: p.container_type == ^type and p.container_id in ^ids,
        order_by: [asc: p.container_id, asc: p.position],
        select: {p.container_id, p.id}
      )
      |> Repo.all()
      # Group_by → keep first (lowest-position) per container.
      |> Enum.group_by(fn {container_id, _pi_id} -> container_id end)
      |> Enum.map(fn {container_id, [{_cid, pi_id} | _]} ->
        {{type, container_id}, pi_id}
      end)
    end)
    |> Map.new()
  end

  @doc """
  Resolves any entity id + current possession to a **presentable
  identity** — a `{kind, id}` pair — applying the single movie-vs-collection
  hoist rule. This is the one authority every read surface consults
  (browse grid, detail modal, now-playing), so the surfaces can never
  disagree about whether something is a movie or a collection.

  Rules:

    * standalone movie (present) → `{:movie, id}`
    * collection with exactly one present movie → `{:movie, sole_child_id}`
      (the collection is hoisted away; the child carries a collection
      reference for the badge)
    * collection with two or more present movies → `{:movie_series, id}`
    * a movie inside a 2+-present collection → `{:movie_series, ms_id}`
      (it isn't a top-level entity; its collection is — matches the grid)
    * tv series with a present episode → `{:tv_series, id}`
    * present video object → `{:video_object, id}`
    * anything absent / unknown → `:not_found`
  """
  @spec resolve_presentable(Ecto.UUID.t()) ::
          {:tv_series | :movie_series | :movie | :video_object, Ecto.UUID.t()} | :not_found
  def resolve_presentable(id) when is_binary(id) do
    cond do
      tv_series_present?(id) -> {:tv_series, id}
      Repo.exists?(from(ms in MovieSeries, where: ms.id == ^id)) -> resolve_collection(id)
      movie = Repo.get(Movie, id) -> resolve_movie(movie)
      video_object_present?(id) -> {:video_object, id}
      true -> :not_found
    end
  end

  defp resolve_collection(movie_series_id) do
    case Repo.all(PresentableQueries.present_movie_ids(movie_series_id)) do
      [] -> :not_found
      [sole_child_id] -> {:movie, sole_child_id}
      _multiple -> {:movie_series, movie_series_id}
    end
  end

  defp resolve_movie(%Movie{id: id, movie_series_id: nil}) do
    if movie_present?(id), do: {:movie, id}, else: :not_found
  end

  defp resolve_movie(%Movie{id: id, movie_series_id: movie_series_id}) do
    case Repo.all(PresentableQueries.present_movie_ids(movie_series_id)) do
      [_, _ | _] = _multiple -> {:movie_series, movie_series_id}
      _zero_or_one -> if movie_present?(id), do: {:movie, id}, else: :not_found
    end
  end

  defp tv_series_present?(tv_series_id) do
    Repo.exists?(
      from(wf in WatchedFile,
        join: pi in PlayableItem,
        on: pi.id == wf.playable_item_id and pi.container_type == :episode,
        join: e in Episode,
        on: e.id == pi.container_id,
        join: s in Season,
        on: s.id == e.season_id,
        where: s.tv_series_id == ^tv_series_id
      )
    )
  end

  defp movie_present?(movie_id), do: container_present?(:movie, movie_id)
  defp video_object_present?(video_object_id), do: container_present?(:video_object, video_object_id)

  defp container_present?(container_type, container_id) do
    Repo.exists?(
      from(wf in WatchedFile,
        join: pi in PlayableItem,
        on: pi.id == wf.playable_item_id and pi.container_type == ^container_type,
        where: pi.container_id == ^container_id
      )
    )
  end

  @doc """
  Loads a single library entry shaped for the detail modal — the
  `%{entity, progress, progress_records}` triple every host LiveView
  assigns to `:selected_entry`.

  Reads from `MediaCentaur.Library.Views.Detail` (Pillar-2 ETS
  projection, microsecond reads in production; live DB-fallback in test
  mode) — probes each container kind in turn and converts the first
  match's `DetailItem` to the legacy entity-map shape via
  `Views.DetailItem.to_entity_map/1`. Progress records come from
  `list_progress_records_for_container/2`; the summary from
  `ProgressSummary.compute/2`.

  Returns `:not_found` when no container matches *and has at least one
  present file* — orphan entities (record exists, no `WatchedFile`)
  don't appear in the modal. Same gating
  `Browser.fetch_typed_entries_by_ids/1` applied pre-Phase-3.2; the
  presence check now walks the projection's `present?` flags (or
  `:seasons/:movies` trees for series containers).

  Library Schema v2 Phase 3.2 Task D flipped this from the
  `Browser + load_extras_for_entity` chain to the projection.
  `load_extras_for_entity/1` is retired — extras flow on the DetailItem
  now.
  """
  @spec load_modal_entry(Ecto.UUID.t()) ::
          {:ok, %{entity: map(), progress: map() | nil, progress_records: list()}}
          | :not_found
  def load_modal_entry(id) when is_binary(id) do
    # Route through the single presentable authority: it applies the hoist
    # rule once (so opening a hoisted collection by its series id correctly
    # lands on the sole movie), then we build the view for the resolved
    # kind. `to_entity_map/1` keys off the projection's `presented_as`, so
    # the resolved kind and the built entity always agree.
    with {kind, resolved_id} <- resolve_presentable(id),
         item when not is_nil(item) <- present_detail_for(kind, resolved_id) do
      {:ok, build_modal_entry(kind, item, resolved_id)}
    else
      _ -> :not_found
    end
  end

  defp present_detail_for(container_type, id) do
    case __MODULE__.Views.detail_by_container(container_type, id) do
      nil ->
        nil

      %__MODULE__.Views.DetailItem{} = item ->
        if any_present?(container_type, item), do: item
    end
  end

  defp any_present?(:tv_series, %__MODULE__.Views.DetailItem{seasons: seasons}) do
    Enum.any?(seasons || [], fn season ->
      Enum.any?(season.episodes || [], & &1.present?)
    end)
  end

  defp any_present?(:movie_series, %__MODULE__.Views.DetailItem{movies: movies}) do
    Enum.any?(movies || [], & &1.present?)
  end

  defp any_present?(_type, %__MODULE__.Views.DetailItem{present?: present}), do: present == true

  defp build_modal_entry(container_type, item, id) do
    entity = item |> __MODULE__.Views.DetailItem.to_entity_map() |> MediaTrackOverrides.put_on_entity()
    progress_records = ProgressRecords.list_for_container(container_type, id)
    progress = MediaCentaur.Library.ProgressSummary.compute(entity, progress_records)

    %{entity: entity, progress: progress, progress_records: progress_records}
  end

  # ---------------------------------------------------------------------------

  @doc """
  Lists the `Library.Image` rows owned by `(owner_type, owner_id)`.

  The discriminator pair is the canonical image ownership key
  (Library Schema v2 Phase 1) — `owner_type` is one of `:movie`,
  `:episode`, `:tv_series`, `:movie_series`, `:video_object`. Used by the
  inbound link-time artwork backfill to learn which roles a container is
  already missing.
  """
  @spec list_images(atom(), Ecto.UUID.t()) :: [Image.t()]
  def list_images(owner_type, owner_id) when is_atom(owner_type) and is_binary(owner_id) do
    Repo.all(from i in Image, where: i.owner_type == ^owner_type and i.owner_id == ^owner_id)
  end

  @doc """
  Resolves logo URLs for a list of `{media_type, entity_id}` pairs in a single
  query. Returns a `%{entity_id => "/media-images/<content_url>"}` map for any
  pair whose corresponding entity has a logo image. Entries without a logo are
  simply absent from the result.

  Used by views that render tracked-show cards (Upcoming, Coming Up) so they
  can fall back from typography to the show logo without per-card lookups.
  """
  @spec logo_urls_for_entities([{:movie | :tv_series, Ecto.UUID.t()}]) :: %{
          Ecto.UUID.t() => String.t()
        }
  def logo_urls_for_entities([]), do: %{}

  def logo_urls_for_entities(pairs) when is_list(pairs) do
    movie_ids = for {:movie, id} <- pairs, is_binary(id), do: id
    tv_ids = for {:tv_series, id} <- pairs, is_binary(id), do: id

    rows =
      Repo.all(
        from i in Image,
          where:
            i.role == "logo" and
              ((i.owner_type == :movie and i.owner_id in ^movie_ids) or
                 (i.owner_type == :tv_series and i.owner_id in ^tv_ids)),
          select: {i.owner_id, i.content_url}
      )

    Map.new(rows, fn {entity_id, content_url} ->
      {entity_id, Image.web_path(content_url)}
    end)
  end

  # ---------------------------------------------------------------------------
  # ExternalId
  # ---------------------------------------------------------------------------

  def create_external_id(attrs) do
    Repo.insert(ExternalId.create_changeset(OwnerRef.normalise(attrs, :external_id)))
  end

  def create_external_id!(attrs), do: Repo.bang!(create_external_id(attrs))

  @doc """
  Returns the container of the given type that owns the given TMDB id
  (via `library_external_ids`), or `nil`.

  Library Schema v2 Phase 2 Task F collapsed the per-type FKs on
  `ExternalId` into a single `(owner_type, owner_id)` discriminator
  pair. This helper joins on the discriminator to fetch the typed
  container in a single query.

  Pass `:tmdb_collection` for MovieSeries; everything else uses
  `:tmdb`.
  """
  @spec find_by_external_id(MediaCentaur.Library.ExternalIds.owner_type(), String.t()) ::
          MediaCentaur.Library.ExternalIds.owner() | nil
  def find_by_external_id(owner_type, external_id) when is_atom(owner_type) and is_binary(external_id) do
    source = if owner_type == :movie_series, do: "tmdb_collection", else: "tmdb"
    schema = schema_for_owner_type(owner_type)

    Repo.one(
      from(r in schema,
        join: e in ExternalId,
        on: e.owner_id == r.id and e.owner_type == ^owner_type,
        where: e.source == ^source and e.external_id == ^external_id,
        limit: 1
      )
    )
  end

  defp schema_for_owner_type(:movie), do: Movie
  defp schema_for_owner_type(:tv_series), do: TVSeries
  defp schema_for_owner_type(:movie_series), do: MovieSeries
  defp schema_for_owner_type(:video_object), do: VideoObject

  @doc """
  Returns `{:ok, file_path}` if the library has a movie with this TMDB
  id whose file has been linked (a `WatchedFile` exists for the movie's
  `PlayableItem`), otherwise `:not_found`. Used by
  `Acquisition.Pursuits.LibraryReconciler` as the safety-net check
  against the PubSub-driven completion path.

  After Library Schema v2 Phase 2 Task I the on-disk path lives on
  `library_watched_files.file_path` via `PlayableItem`; this query
  walks `Movie → PlayableItem → WatchedFile` rather than reading a
  former `content_url` column on Movie.
  """
  @spec find_present_movie(String.t()) :: {:ok, String.t()} | :not_found
  def find_present_movie(tmdb_id) when is_binary(tmdb_id) do
    case Repo.one(
           from(m in Movie,
             join: e in ExternalId,
             on: e.owner_id == m.id and e.owner_type == :movie,
             join: pi in PlayableItem,
             on: pi.container_id == m.id and pi.container_type == :movie,
             join: w in WatchedFile,
             on: w.playable_item_id == pi.id,
             where: e.source == "tmdb" and e.external_id == ^tmdb_id,
             select: w.file_path,
             limit: 1
           )
         ) do
      nil -> :not_found
      url -> {:ok, url}
    end
  end

  @doc """
  Returns `{:ok, file_path}` if the library has an episode for the
  given `(tmdb_id, season_number, episode_number)` tuple whose file has
  been linked, otherwise `:not_found`. Joins through
  `TVSeries → Season → Episode → PlayableItem → WatchedFile` in a
  single query.
  """
  @spec find_present_episode(String.t(), integer(), integer()) ::
          {:ok, String.t()} | :not_found
  def find_present_episode(tmdb_id, season_number, episode_number)
      when is_binary(tmdb_id) and is_integer(season_number) and is_integer(episode_number) do
    case Repo.one(
           from(e in Episode,
             join: s in Season,
             on: s.id == e.season_id,
             join: t in TVSeries,
             on: t.id == s.tv_series_id,
             join: ext in ExternalId,
             on: ext.owner_id == t.id and ext.owner_type == :tv_series,
             join: pi in PlayableItem,
             on: pi.container_id == e.id and pi.container_type == :episode,
             join: w in WatchedFile,
             on: w.playable_item_id == pi.id,
             where:
               ext.source == "tmdb" and ext.external_id == ^tmdb_id and
                 s.season_number == ^season_number and
                 e.episode_number == ^episode_number,
             select: w.file_path,
             limit: 1
           )
         ) do
      nil -> :not_found
      url -> {:ok, url}
    end
  end

  @doc """
  Returns the set of `{season_number, episode_number}` pairs for a TV
  series whose episode has a linked file on disk — the "present-set" used
  by reconciliation to mark which canonical spine nodes are already filled.
  """
  @spec present_episode_keys(Ecto.UUID.t()) :: MapSet.t({integer(), integer()})
  def present_episode_keys(tv_series_id) when is_binary(tv_series_id) do
    from(e in Episode,
      join: s in Season,
      on: s.id == e.season_id,
      join: pi in PlayableItem,
      on: pi.container_id == e.id and pi.container_type == :episode,
      join: w in WatchedFile,
      on: w.playable_item_id == pi.id,
      where: s.tv_series_id == ^tv_series_id,
      distinct: true,
      select: {s.season_number, e.episode_number}
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Returns every on-disk file path currently linked to a `PlayableItem`
  (i.e. present in the library).

  Used by `Acquisition.Pursuits.LibraryReconciler` to satisfy
  prowlarr-query pursuits, which carry no TMDB id to match on — the only
  binding back to the library is the downloaded file's name, so the
  reconciler matches the pursuit's release title against these basenames.
  """
  @spec list_present_file_paths() :: [String.t()]
  def list_present_file_paths do
    Repo.all(from(w in WatchedFile, select: w.file_path))
  end

  @doc """
  Returns `{tv_series_id, tmdb_id}` pairs for TV series in the given list
  that have a TMDB ExternalId row.
  """
  def tmdb_ids_for_tv_series(tv_series_ids) when is_list(tv_series_ids) do
    Repo.all(
      from(t in TVSeries,
        join: e in ExternalId,
        on: e.owner_id == t.id and e.owner_type == :tv_series,
        where: t.id in ^tv_series_ids and e.source == "tmdb",
        select: {t.id, e.external_id}
      )
    )
  end

  @doc """
  Returns `{movie_id, tmdb_id}` pairs for movies in the given list that
  have a TMDB ExternalId row. Mirror of `tmdb_ids_for_tv_series/1` —
  release tracking uses this to detect when a tracked movie has just
  landed in the library so it can close out the tracking item.
  """
  def tmdb_ids_for_movies(movie_ids) when is_list(movie_ids) do
    Repo.all(
      from(m in Movie,
        join: e in ExternalId,
        on: e.owner_id == m.id and e.owner_type == :movie,
        where: m.id in ^movie_ids and e.source == "tmdb",
        select: {m.id, e.external_id}
      )
    )
  end

  @doc """
  Returns every entity in the library that has a TMDB ExternalId,
  tagged with its type. Used by ReleaseTracking to scan for tracking
  candidates.

  Each row is `%{source: String.t(), external_id: String.t(),
  owner_type: atom(), owner_id: Ecto.UUID.t()}`. The `:source` is
  `"tmdb"` for movies / TV / video objects and `"tmdb_collection"` for
  movie series; `:owner_type` is the canonical container type atom.

  Standalone movies (no `movie_series_id`) are surfaced; movies that
  belong to a movie_series are skipped — release tracking handles them
  through the collection.
  """
  def list_tmdb_entities do
    tv_and_movie_series =
      Repo.all(
        from(e in ExternalId,
          where:
            (e.owner_type == :tv_series and e.source == "tmdb") or
              (e.owner_type == :movie_series and e.source == "tmdb_collection"),
          select: %{
            source: e.source,
            external_id: e.external_id,
            owner_type: e.owner_type,
            owner_id: e.owner_id
          }
        )
      )

    standalone_movies =
      Repo.all(
        from(m in Movie,
          join: e in ExternalId,
          on: e.owner_id == m.id and e.owner_type == :movie,
          where: e.source == "tmdb" and is_nil(m.movie_series_id),
          select: %{
            source: e.source,
            external_id: e.external_id,
            owner_type: e.owner_type,
            owner_id: e.owner_id
          }
        )
      )

    tv_and_movie_series ++ standalone_movies
  end

  # ---------------------------------------------------------------------------
  # ---------------------------------------------------------------------------
  # ---------------------------------------------------------------------------
  # ChangeEntry
  # ---------------------------------------------------------------------------

  def create_change_entry(attrs) do
    Repo.insert(ChangeEntry.create_changeset(attrs))
  end

  def create_change_entry!(attrs), do: Repo.bang!(create_change_entry(attrs))

  def list_recent_changes(limit, since) do
    query =
      from(c in ChangeEntry,
        order_by: [{:desc, c.inserted_at}, {:desc, fragment("rowid")}],
        limit: ^limit
      )

    query =
      if since do
        from(c in query, where: c.inserted_at >= ^since)
      else
        query
      end

    Repo.all(query)
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @doc """
  Broadcasts `{:entities_changed, entity_ids}` to the `"library:updates"` PubSub topic.
  """
  defdelegate broadcast_entities_changed(entity_ids), to: MediaCentaur.Library.Helpers

  # ---------------------------------------------------------------------------
  # HomeLive Facade — query + display-shaping lives in Library.HomeFeed;
  # these delegators keep the context's public API stable for the Views.*
  # projections and Status.
  # ---------------------------------------------------------------------------

  @doc "See `MediaCentaur.Library.HomeFeed.list_in_progress/1` (Continue Watching)."
  def list_in_progress(opts \\ []), do: HomeFeed.list_in_progress(opts)

  @doc "See `MediaCentaur.Library.HomeFeed.list_recently_added/1`."
  def list_recently_added(opts \\ []), do: HomeFeed.list_recently_added(opts)

  @doc "See `MediaCentaur.Library.HomeFeed.list_hero_candidates/1`."
  def list_hero_candidates(opts \\ []), do: HomeFeed.list_hero_candidates(opts)

  @doc """
  Library-wide entity, episode, file and image counts for the Status page's
  operational dashboard.

  A `Movie` belonging to a `MovieSeries` is part of a collection, not a
  standalone title, so it is excluded from the `:movie` count. That
  distinction is the library's own rule and lives here, not in the caller.
  """
  @spec stats() :: %{
          episodes: non_neg_integer(),
          files: non_neg_integer(),
          images: non_neg_integer(),
          by_type: %{
            movie: non_neg_integer(),
            tv_series: non_neg_integer(),
            movie_series: non_neg_integer(),
            video_object: non_neg_integer()
          }
        }
  def stats do
    %{
      episodes: count_rows(Episode),
      files: count_rows(WatchedFile),
      images: count_rows(Image),
      by_type: %{
        movie: Repo.one(from(m in Movie, where: is_nil(m.movie_series_id), select: count(m.id))),
        tv_series: count_rows(TVSeries),
        movie_series: count_rows(MovieSeries),
        video_object: count_rows(VideoObject)
      }
    }
  end

  defp count_rows(schema), do: Repo.one(from(record in schema, select: count(record.id)))

  # ---------------------------------------------------------------------------
  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
end
