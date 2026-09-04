defmodule MediaCentaurWeb.ViewModel.CollectionDetail do
  @moduledoc """
  Presentation view model for the movie-collection detail modal — the
  movie-side counterpart of `MediaCentaurWeb.ViewModel.SeriesDetail`.

  Composes data from two bounded contexts —
  `MediaCentaur.Library` (entity, member movies, watch progress) and
  `MediaCentaur.ReleaseTracking` (announced parts of tracked
  collections) — into a single typed struct the modal LiveView assigns
  and the detail panel renders.

  `compose/1` does the cross-context fetch and delegates to `build/4`,
  which is pure and unit-tested without a database. Callers reach this
  composer through the detail modal's single loader
  (`MediaCentaurWeb.Live.EntityModal`), which resolves the container
  kind via `MediaCentaur.Library.Presentable` first — so `compose/1` is
  only ever asked about ids already known to present as `:movie_series`.

  Like `SeriesDetail`, release records are read by field, not struct
  match (`MediaCentaur.ReleaseTracking.Release` is not exported across
  its boundary per ADR-029). The shape contract is documented on
  `build/4`: `[%{part_tmdb_id, title, air_date}]`.
  """

  alias MediaCentaur.Library
  alias MediaCentaur.Library.EpisodeList
  alias MediaCentaur.Library.MovieList
  alias MediaCentaur.Library.ProgressSummary
  alias MediaCentaur.Library.Views.DetailItem
  alias MediaCentaur.Playback.ResumeTarget
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaurWeb.ViewModel.MovieListItem

  @enforce_keys [:entity, :movies]
  defstruct [
    :entity,
    :progress,
    :progress_records,
    :tracking_status,
    :movies,
    :extras,
    :resume_target,
    # Cached input to `build/4` — kept on the struct so in-memory
    # progress merges can rebuild `movies` (which carries per-item
    # state) without a fresh DB query per playback tick.
    :releases
  ]

  @type t :: %__MODULE__{
          entity: map(),
          progress: map() | nil,
          progress_records: list(),
          tracking_status: :watching | :ignored | nil,
          movies: [MovieListItem.t()],
          extras: list(),
          resume_target: map() | nil,
          releases: [map()]
        }

  @doc """
  Loads + composes the view model for a movie collection. Returns
  `:not_found` if no `:movie_series` projection row matches
  `entity_id`.

  Reads the Library half from `MediaCentaur.Library.Views.Detail`
  (Pillar-2 ETS projection, microsecond reads in production; falls back
  to a live build in test mode). Cross-context overlays (ReleaseTracking
  releases, tracking_status) compose at this layer per ADR-029.

  Computes the resume target via `MediaCentaur.Playback.ResumeTarget`
  on the loaded entry, so callers don't have to thread it separately.
  """
  @spec compose(Ecto.UUID.t()) :: {:ok, t()} | :not_found
  def compose(entity_id) when is_binary(entity_id) do
    case Library.Views.detail_by_container(:movie_series, entity_id) do
      %DetailItem{} = detail_item ->
        {:ok, compose_from_detail(detail_item, entity_id)}

      nil ->
        :not_found
    end
  end

  defp compose_from_detail(detail_item, entity_id) do
    entity = detail_item |> DetailItem.to_entity_view() |> Library.MediaTrackOverrides.put_on_entity()
    progress_records = Library.ProgressRecords.list_for_container(:movie_series, entity_id)
    progress_summary = ProgressSummary.compute(entity, progress_records)

    entry = %{
      entity: entity,
      progress: progress_summary,
      progress_records: progress_records
    }

    releases =
      ReleaseTracking.list_relevant_releases_for_library_container(entity_id, :movie)

    tracking_status = lookup_tracking_status(entity)
    resume_target = ResumeTarget.compute(entity, progress_records)
    build(entry, releases, tracking_status, resume_target)
  end

  @doc """
  Pure: builds a `%CollectionDetail{}` from a loaded library entry, the
  releases relevant to it, the tracking status, and the precomputed
  resume target.

  Releases are expected to be `MediaCentaur.ReleaseTracking.Release.t()`
  rows (or any map with the same fields: `part_tmdb_id, title,
  air_date`). Collection parts carry no season/episode numbers; a part
  may arrive as several release rows (theatrical/digital dates from the
  solo-movie refresh fallback), so rows are deduped per `part_tmdb_id` —
  dated rows beat undated ones, earliest date wins.

  No database access. Tests construct the inputs as fixtures.
  """
  @spec build(map(), [map()], :watching | :ignored | nil, map() | nil) :: t()
  def build(entry, releases, tracking_status, resume_target) do
    progress_by_movie_id = index_progress_by_movie_id(entry.progress_records)
    resume_target_id = resume_target_id(resume_target)

    library_items =
      (entry.entity.movies || [])
      |> MovieList.sort_movies()
      |> Enum.filter(& &1.content_url)
      |> Enum.map(fn movie ->
        progress = Map.get(progress_by_movie_id, movie.id)

        %MovieListItem.Library{
          movie: movie,
          progress: progress,
          state: EpisodeList.state_from_progress(progress),
          is_resume_target: resume_target_id != nil and movie.id == resume_target_id
        }
      end)

    library_tmdb_ids =
      library_items
      |> Enum.map(&Map.get(&1.movie, :tmdb_id))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    %__MODULE__{
      entity: entry.entity,
      progress: entry.progress,
      progress_records: entry.progress_records,
      tracking_status: tracking_status,
      movies: library_items ++ upcoming_items(releases, library_tmdb_ids),
      extras: entry.entity.extras || [],
      resume_target: resume_target,
      releases: releases
    }
  end

  @doc """
  Updates the in-memory view model with new progress data and rebuilds
  the item list. Used by the modal's progress-tick merge path so
  per-movie `state` and `is_resume_target` flags stay current without a
  fresh DB query.

  Pure: reuses the cached `releases` and `tracking_status` on the
  existing struct.
  """
  @spec with_progress(t(), map() | nil, list(), map() | nil) :: t()
  def with_progress(%__MODULE__{} = collection_detail, progress, progress_records, resume_target) do
    entry = %{
      entity: collection_detail.entity,
      progress: progress,
      progress_records: progress_records
    }

    build(entry, collection_detail.releases || [], collection_detail.tracking_status, resume_target)
  end

  # --- Member selection (UIDR-023 movie-first modal) ---

  @doc """
  Resolves which library member the modal shows. An explicit `member_id`
  wins when it names a library member; otherwise the resume target;
  otherwise the first library member (chronological order). `nil` when
  the collection has no playable members.

  Stale ids (deleted member, an upcoming part's tmdb id, a refresh
  race) fall through to the default rather than erroring — the URL is a
  preference, not an invariant.
  """
  @spec select_member(t(), Ecto.UUID.t() | nil) :: MovieListItem.Library.t() | nil
  def select_member(%__MODULE__{movies: movies}, member_id) do
    library_items = Enum.filter(movies, &match?(%MovieListItem.Library{}, &1))

    find_member(library_items, member_id) ||
      Enum.find(library_items, & &1.is_resume_target) ||
      List.first(library_items)
  end

  defp find_member(_library_items, nil), do: nil
  defp find_member(library_items, member_id), do: Enum.find(library_items, &(&1.movie.id == member_id))

  @doc """
  Composes the selected member into the `:movie`-shaped entity map the
  standalone-movie detail panel consumes — the mechanism that keeps the
  collection modal on the same component family as a bare movie
  (UIDR-023): downstream components never learn a collection is
  involved.

  Handles both member shapes (`Library.Movie` struct or the lean
  projection map); unloaded associations read as empty lists.
  """
  @spec member_subject(MovieListItem.Library.t()) :: map()
  def member_subject(%MovieListItem.Library{movie: movie}) do
    %{
      id: movie.id,
      type: :movie,
      collection: nil,
      name: movie.name,
      description: Map.get(movie, :description),
      date_published: Map.get(movie, :date_published),
      content_url: Map.get(movie, :content_url),
      url: Map.get(movie, :url),
      tagline: Map.get(movie, :tagline),
      genres: Map.get(movie, :genres),
      studio: Map.get(movie, :studio),
      country_code: Map.get(movie, :country_code),
      original_language: Map.get(movie, :original_language),
      network: nil,
      status: Map.get(movie, :status),
      duration_seconds: Map.get(movie, :duration_seconds),
      content_rating: Map.get(movie, :content_rating),
      aggregate_rating_value: Map.get(movie, :aggregate_rating_value),
      vote_count: Map.get(movie, :vote_count),
      number_of_seasons: nil,
      director: Map.get(movie, :director),
      cast: loaded_list(Map.get(movie, :cast)),
      crew: loaded_list(Map.get(movie, :crew)),
      extras: [],
      external_ids: [],
      imdb_id: nil,
      tmdb_id: Map.get(movie, :tmdb_id),
      images: loaded_list(Map.get(movie, :images)),
      seasons: [],
      movies: [],
      watched_files: [],
      subtitle_tracks: [],
      extra_progress: []
    }
  end

  # Ecto.Association.NotLoaded (a Movie struct outside the projection
  # path) reads as [] — the subject map promises lists.
  defp loaded_list(list) when is_list(list), do: list
  defp loaded_list(_not_loaded), do: []

  # --- Upcoming overlay ---

  # One row per announced part: group the release rows by part_tmdb_id,
  # keep the best-dated one (dated beats undated, earliest date wins),
  # then order the parts by air date with undated parts last. Parts
  # matching a library movie's tmdb id are dropped — the release query
  # already excludes marked-in-library rows, this covers the window
  # before the tracking refresh marks a freshly-imported part.
  defp upcoming_items(releases, library_tmdb_ids) do
    releases
    |> Enum.reject(&MapSet.member?(library_tmdb_ids, &1.part_tmdb_id))
    |> Enum.group_by(& &1.part_tmdb_id)
    |> Enum.map(fn {_part_tmdb_id, rows} -> Enum.min_by(rows, &air_date_sort_key/1) end)
    |> Enum.sort_by(&air_date_sort_key/1)
    |> Enum.map(fn release ->
      %MovieListItem.Upcoming{
        part_tmdb_id: release.part_tmdb_id,
        title: release.title,
        air_date: release.air_date,
        sub_status: upcoming_sub_status(release)
      }
    end)
  end

  # ISO 8601 sorts lexicographically the same as chronologically; the
  # sentinel sorts undated rows after any dated one.
  defp air_date_sort_key(%{air_date: %Date{} = air_date}), do: Date.to_iso8601(air_date)
  defp air_date_sort_key(_release), do: "9999-99-99"

  # The DB query already excludes aired-and-in-library rows, so an aired
  # release here is not-in-library; an unaired one has a future/absent
  # air_date. Same derivation as `SeriesDetail`.
  defp upcoming_sub_status(release) do
    if aired?(release), do: :aired_not_in_library, else: :unaired
  end

  defp aired?(%{air_date: %Date{} = air_date}), do: Date.compare(air_date, Date.utc_today()) != :gt
  defp aired?(_release), do: false

  # --- Helpers ---

  defp resume_target_id(%{"targetId" => id}) when is_binary(id), do: id
  defp resume_target_id(_resume_target), do: nil

  defp index_progress_by_movie_id(progress_records) do
    progress_records
    |> Enum.map(fn record -> {EpisodeList.progress_container_id(record), record} end)
    |> Enum.reject(fn {movie_id, _record} -> is_nil(movie_id) end)
    |> Map.new()
  end

  defp lookup_tracking_status(%{external_ids: external_ids, type: :movie_series})
       when is_list(external_ids) do
    case Enum.find(external_ids, &match?(%{source: "tmdb_collection"}, &1)) do
      %{external_id: tmdb_id_str} ->
        case Integer.parse(tmdb_id_str) do
          {tmdb_id, ""} -> ReleaseTracking.tracking_status({tmdb_id, :movie})
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp lookup_tracking_status(_entity), do: nil
end
