defmodule MediaCentaur.Library.ProgressRecords do
  @moduledoc """
  Persisted watch state for the library — the database side of progress.
  Every `WatchProgress` read and write names the profile first (ADR-078).

  Two tables live here because the library has two kinds of watchable
  thing:

    * `WatchProgress`, keyed by `(profile_id, playable_item_id)`, for the
      playable leaves (Movie / Episode / VideoObject).
    * `ExtraProgress`, keyed by `extra_id`, for bonus features, which are
      not `PlayableItem`s.

  They are deliberately adjacent. The two carry the *same seven
  operations* and differ only in their key, and that duplication is a
  standing convergence point — it resolves when `Extra` becomes a
  `PlayableItem`, not before. Keeping them in one module makes the
  parallel visible rather than filing it 200 lines apart.

  `mark_completed/1` and `mark_incomplete/1` already dispatch on the
  struct, so callers holding either kind of record use one name. Note
  the asymmetry in the adjacent clauses: completing a `WatchProgress`
  broadcasts `{:entity_watch_completed, record}`, completing an
  `ExtraProgress` does not — extras do not participate in Continue
  Watching.

  Not to be confused with `Library.Progress`, which is the in-memory ETS
  projection that debounce-flushes *into* this module.

  Reading a record is here too: `progress_container_id/1` resolves the leaf
  id off the preloaded `PlayableItem`, `state_from_progress/1` derives the
  watch state, and `index_progress_by_key/1` keys a list of records by leaf.
  They lived in `Library.EpisodeOrder` until 2026-09-13, which is why a movie
  view model used to call an episode-named module for them.
  """

  import Ecto.Query

  @doc """
  Indexes progress records by their container id (Movie or Episode id),
  resolved through the linked `PlayableItem`. Expects `:playable_item` to
  be preloaded on each record (Library Schema v2 Phase 2 Task C — the
  three direct FKs `movie_id` / `episode_id` / `video_object_id` no
  longer exist on `WatchProgress`).
  """
  def index_progress_by_key(progress_records) do
    Map.new(progress_records, fn record ->
      {progress_container_id(record), record}
    end)
  end

  @doc """
  Returns the container id (Movie / Episode / VideoObject UUID) for a
  WatchProgress record. Requires `:playable_item` to be preloaded.
  Returns `nil` when the association isn't loaded — callers that key on
  this value will lose the entry, which is the same failure mode as the
  previous direct-FK accessor when the FK was nil.
  """
  def progress_container_id(%{playable_item: %{container_id: id}}), do: id
  def progress_container_id(_), do: nil

  @doc """
  Maps a `WatchProgress` record (or `nil`) to the three-state UI atom
  used by the detail panel and the SeriesDetail view model:

  - `:unwatched` — no progress, or progress at position 0 and not completed
  - `:current`   — progress past position 0 but not completed
  - `:watched`   — `completed: true`

  Shared between the rendering layer (`DetailPanel`) and the
  composition layer (`SeriesDetail`) so the rule lives in one place.
  """
  @spec state_from_progress(map() | nil) :: :unwatched | :current | :watched
  def state_from_progress(nil), do: :unwatched

  def state_from_progress(progress) do
    cond do
      progress.completed -> :watched
      (progress.position_seconds || 0.0) > 0.0 -> :current
      true -> :unwatched
    end
  end

  alias MediaCentaur.Library.{
    Episode,
    Episodes,
    ExtraProgress,
    Movie,
    PlayableItem,
    PlayableItems,
    PresentableQueries,
    Season,
    WatchProgress,
    Writes
  }

  alias MediaCentaur.{Repo, Topics}

  @type container_type :: :tv_series | :movie_series | :movie | :video_object

  @type summary :: %{
          current_episode: %{season: integer(), episode: integer()} | nil,
          episode_position_seconds: float(),
          episode_duration_seconds: float(),
          episodes_completed: non_neg_integer(),
          episodes_total: non_neg_integer(),
          last_watched_at: DateTime.t() | nil
        }

  # ---- shared lifecycle (struct-dispatched) --------------------------------

  @doc """
  Flips a progress record to completed.

  A `WatchProgress` transitioning to completed broadcasts
  `{:entity_watch_completed, record}` so Continue Watching and the watch
  history react; re-completing an already-complete record does not
  re-broadcast. `ExtraProgress` never broadcasts.
  """
  @spec mark_completed(WatchProgress.t() | ExtraProgress.t()) ::
          {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def mark_completed(%WatchProgress{} = progress) do
    transitioning? = not progress.completed

    with {:ok, updated} <- Repo.update(WatchProgress.mark_completed_changeset(progress)) do
      if transitioning? do
        Topics.publish(
          Topics.library_watch_completed(),
          {:entity_watch_completed, updated}
        )
      end

      {:ok, updated}
    end
  end

  def mark_completed(%ExtraProgress{} = progress) do
    Repo.update(ExtraProgress.mark_completed_changeset(progress))
  end

  @doc "As `mark_completed/1`, raising on a rejected changeset."
  @spec mark_completed!(WatchProgress.t() | ExtraProgress.t()) :: struct()
  def mark_completed!(progress), do: Repo.bang!(mark_completed(progress))

  @doc "Flips a progress record back to incomplete."
  @spec mark_incomplete(WatchProgress.t() | ExtraProgress.t()) ::
          {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def mark_incomplete(%WatchProgress{} = progress),
    do: Repo.update(WatchProgress.mark_incomplete_changeset(progress))

  def mark_incomplete(%ExtraProgress{} = progress),
    do: Repo.update(ExtraProgress.mark_incomplete_changeset(progress))

  @doc "As `mark_incomplete/1`, raising on a rejected changeset."
  @spec mark_incomplete!(WatchProgress.t() | ExtraProgress.t()) :: struct()
  def mark_incomplete!(progress), do: Repo.bang!(mark_incomplete(progress))

  # ---- WatchProgress -------------------------------------------------------

  @doc "Every `WatchProgress` row, of every profile."
  @spec list_all() :: [WatchProgress.t()]
  def list_all, do: Repo.all(WatchProgress)

  @doc """
  Fetches `profile_id`'s watch-progress row for a leaf container,
  resolving through its `PlayableItem`.
  """
  @spec fetch_for_container(Ecto.UUID.t(), PlayableItem.container_type(), Ecto.UUID.t()) ::
          {:ok, WatchProgress.t()} | {:error, :not_found}
  def fetch_for_container(profile_id, container_type, container_id) when is_binary(profile_id) do
    query =
      from(wp in WatchProgress,
        join: pi in PlayableItem,
        on: pi.id == wp.playable_item_id,
        where:
          wp.profile_id == ^profile_id and pi.container_type == ^container_type and
            pi.container_id == ^container_id,
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @doc """
  Upserts `profile_id`'s watch-progress row for a leaf container,
  resolving (and creating if needed) its canonical `PlayableItem` first.

  The position is derived by `PlayableItems.canonical_position/2` — the
  only per-type behaviour in this path.
  """
  @spec find_or_create_for_container(
          Ecto.UUID.t(),
          PlayableItem.container_type(),
          Ecto.UUID.t(),
          map()
        ) :: {:ok, WatchProgress.t()} | {:error, term()}
  def find_or_create_for_container(profile_id, container_type, container_id, attrs \\ %{})
      when is_binary(profile_id) do
    position = PlayableItems.canonical_position(container_type, container_id)

    with {:ok, playable_item} <- PlayableItems.find_or_create(container_type, container_id, position) do
      attrs =
        attrs
        |> Map.new()
        |> Map.merge(%{profile_id: profile_id, playable_item_id: playable_item.id})

      Writes.upsert_by(
        WatchProgress,
        [profile_id: profile_id, playable_item_id: playable_item.id],
        attrs
      )
    end
  end

  @doc """
  The progress worker's flush: writes one in-memory row through to its
  `(profile_id, playable_item_id)` row, raising on failure — a flush
  error means the in-memory row is out of sync with the DB and must
  surface rather than silently drop state.
  """
  @spec upsert_by_profile_item!(map()) :: WatchProgress.t()
  def upsert_by_profile_item!(%{profile_id: profile_id, playable_item_id: playable_item_id} = attrs)
      when is_binary(profile_id) and is_binary(playable_item_id) do
    case Writes.upsert_by(
           WatchProgress,
           [profile_id: profile_id, playable_item_id: playable_item_id],
           attrs
         ) do
      {:ok, record} -> record
      {:error, changeset} -> raise "WatchProgress flush failed: #{inspect(changeset)}"
    end
  end

  @doc """
  Looks up or creates `profile_id`'s row for a `playable_item_id`.

  Used by `Library.Progress.complete/2` — completion has to resolve the
  persisted row, creating one if necessary, before flipping `completed`.
  """
  @spec find_or_create_by_playable_item(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, WatchProgress.t()} | {:error, term()}
  def find_or_create_by_playable_item(profile_id, playable_item_id)
      when is_binary(profile_id) and is_binary(playable_item_id) do
    case Repo.get_by(WatchProgress, profile_id: profile_id, playable_item_id: playable_item_id) do
      nil ->
        Writes.upsert_by(
          WatchProgress,
          [profile_id: profile_id, playable_item_id: playable_item_id],
          %{profile_id: profile_id, playable_item_id: playable_item_id}
        )

      record ->
        {:ok, record}
    end
  end

  @doc """
  Every `WatchProgress` record of `profile_id` beneath a container, each
  carrying a synthesised `:playable_item` map (`container_type` +
  `container_id`) so consumers can key by leaf-container UUID without a
  separate `belongs_to :playable_item` preload.

  The one way a title's progress is read — the detail modal, playback
  resolution and the Browse rebuild all come through here.

  Returns `[]` for an unknown container id, or one with no rows beneath
  any leaf.
  """
  @spec list_for_container(Ecto.UUID.t(), container_type(), Ecto.UUID.t()) :: [WatchProgress.t()]
  def list_for_container(profile_id, :tv_series, id), do: list_for_tv_series(profile_id, id)
  def list_for_container(profile_id, :movie_series, id), do: list_for_movie_series(profile_id, id)
  def list_for_container(profile_id, :movie, id), do: list_for_leaf(profile_id, :movie, id)
  def list_for_container(profile_id, :video_object, id), do: list_for_leaf(profile_id, :video_object, id)

  @doc """
  `profile_id`'s progress row of each leaf container (movie, video
  object) in `ids`, keyed by container id, in one query. A leaf without
  a row is absent. The read Continue Watching uses for its single-leaf
  entries.
  """
  @spec progress_by_leaf(Ecto.UUID.t(), :movie | :video_object, [Ecto.UUID.t()]) ::
          %{Ecto.UUID.t() => WatchProgress.t()}
  def progress_by_leaf(_profile_id, _container_type, []), do: %{}

  def progress_by_leaf(profile_id, container_type, ids) when container_type in [:movie, :video_object] do
    profile_id
    |> leaf_rows(container_type, ids)
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Bulk progress lookup for projection consumers (Phase 3.1). Resolves
  `%{entity_id => summary}` for every container UUID in the input that
  has at least one `WatchProgress` row of `profile_id`.

  Each summary carries the shape `Library.ProgressSummary.compute/2`
  returns, plus `:last_watched_at` so consumers that sort by recency
  don't need a separate progress preload. Entities with no progress rows
  are absent from the result (not set to `nil`). Worst case one query
  per container kind in the input set; totals do not scale with row
  count.
  """
  @spec summaries(Ecto.UUID.t(), [Ecto.UUID.t()]) :: %{Ecto.UUID.t() => summary()}
  def summaries(_profile_id, []), do: %{}

  def summaries(profile_id, entity_ids) when is_binary(profile_id) and is_list(entity_ids) do
    %{}
    |> Map.merge(leaf_summaries(profile_id, :movie, entity_ids))
    |> Map.merge(leaf_summaries(profile_id, :video_object, entity_ids))
    |> Map.merge(movie_series_summaries(profile_id, entity_ids))
    |> Map.merge(tv_series_summaries(profile_id, entity_ids))
  end

  @doc "Every profile with at least one progress row — the profiles Continue Watching is built for."
  @spec profile_ids_with_progress() :: [Ecto.UUID.t()]
  def profile_ids_with_progress,
    do:
      Repo.all(from(wp in WatchProgress, distinct: true, select: wp.profile_id, order_by: wp.profile_id))

  # ---- ExtraProgress -------------------------------------------------------

  @doc "Fetches the progress row for an Extra."
  @spec fetch_for_extra(Ecto.UUID.t()) :: {:ok, ExtraProgress.t()} | {:error, :not_found}
  def fetch_for_extra(extra_id) do
    case Repo.get_by(ExtraProgress, extra_id: extra_id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @doc "Upserts the progress row for an Extra."
  @spec find_or_create_for_extra(map()) ::
          {:ok, ExtraProgress.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create_for_extra(attrs),
    do: Writes.upsert_by(ExtraProgress, [extra_id: Writes.attr(attrs, :extra_id)], attrs)

  @doc "As `find_or_create_for_extra/1`, raising on a rejected changeset."
  @spec find_or_create_for_extra!(map()) :: ExtraProgress.t()
  def find_or_create_for_extra!(attrs), do: Repo.bang!(find_or_create_for_extra(attrs))

  # ---- internals -----------------------------------------------------------

  # The three row queries below are the one join each container shape
  # needs, filtered to one profile; the public readers differ only in how
  # they shape the rows.

  # `{container_id, progress}` for each leaf (movie, video object) in `ids`.
  defp leaf_rows(profile_id, container_type, container_ids) do
    from(wp in WatchProgress,
      join: pi in PlayableItem,
      on:
        pi.id == wp.playable_item_id and pi.container_type == ^container_type and
          pi.container_id in ^container_ids,
      where: wp.profile_id == ^profile_id,
      select: {pi.container_id, wp}
    )
  end

  # `{tv_series_id, episode_id, progress}` for each episode beneath the series in `ids`.
  defp episode_rows_by_tv_series(profile_id, tv_series_ids) do
    from(wp in WatchProgress,
      join: pi in PlayableItem,
      on: pi.id == wp.playable_item_id and pi.container_type == :episode,
      join: e in Episode,
      on: e.id == pi.container_id,
      join: s in Season,
      on: s.id == e.season_id,
      where: wp.profile_id == ^profile_id and s.tv_series_id in ^tv_series_ids,
      select: {s.tv_series_id, e.id, wp}
    )
  end

  # `{movie_series_id, movie_id, progress}` for each movie beneath the collections in `ids`.
  defp movie_rows_by_movie_series(profile_id, movie_series_ids) do
    from(wp in WatchProgress,
      join: pi in PlayableItem,
      on: pi.id == wp.playable_item_id and pi.container_type == :movie,
      join: m in Movie,
      on: m.id == pi.container_id,
      where: wp.profile_id == ^profile_id and m.movie_series_id in ^movie_series_ids,
      select: {m.movie_series_id, m.id, wp}
    )
  end

  defp attach_leaf(progress, container_type, container_id),
    do: %{progress | playable_item: %{container_type: container_type, container_id: container_id}}

  defp list_for_tv_series(profile_id, tv_series_id) when is_binary(tv_series_id) do
    profile_id
    |> episode_rows_by_tv_series([tv_series_id])
    |> Repo.all()
    |> Enum.map(fn {_tv_series_id, episode_id, progress} ->
      attach_leaf(progress, :episode, episode_id)
    end)
  end

  defp list_for_movie_series(profile_id, movie_series_id) when is_binary(movie_series_id) do
    profile_id
    |> movie_rows_by_movie_series([movie_series_id])
    |> Repo.all()
    |> Enum.map(fn {_movie_series_id, movie_id, progress} -> attach_leaf(progress, :movie, movie_id) end)
  end

  defp list_for_leaf(profile_id, container_type, container_id) when is_binary(container_id) do
    profile_id
    |> leaf_rows(container_type, [container_id])
    |> Repo.all()
    |> Enum.map(fn {^container_id, progress} -> attach_leaf(progress, container_type, container_id) end)
  end

  # Movies and video objects are single-leaf containers — totals are
  # always 1, so no separate count query is needed.
  defp leaf_summaries(profile_id, container_type, ids) do
    profile_id
    |> leaf_rows(container_type, ids)
    |> Repo.all()
    |> Map.new(fn {container_id, row} ->
      {container_id,
       %{
         current_episode: nil,
         episode_position_seconds: row.position_seconds || 0.0,
         episode_duration_seconds: row.duration_seconds || 0.0,
         episodes_completed: if(row.completed, do: 1, else: 0),
         episodes_total: 1,
         last_watched_at: row.last_watched_at
       }}
    end)
  end

  # TV series: episodes_total counts *present* episodes (those with a
  # WatchedFile) under any season of the series; episodes_completed
  # counts completed progress rows beneath it.
  defp tv_series_summaries(profile_id, ids) do
    profile_id
    |> episode_rows_by_tv_series(ids)
    |> Repo.all()
    |> Enum.map(fn {tv_series_id, _episode_id, row} -> owner_row(tv_series_id, row) end)
    |> summarise(&Episodes.count_available_by_tv_series/1)
  end

  # Movie series: total counts *present* child movies (those with a
  # WatchedFile); completed counts child movies carrying a completed
  # WatchProgress.
  defp movie_series_summaries(profile_id, ids) do
    profile_id
    |> movie_rows_by_movie_series(ids)
    |> Repo.all()
    |> Enum.map(fn {movie_series_id, _movie_id, row} -> owner_row(movie_series_id, row) end)
    |> summarise(&movie_totals_by_movie_series/1)
  end

  defp owner_row(owner_id, row) do
    %{
      owner_id: owner_id,
      completed: row.completed,
      position_seconds: row.position_seconds,
      duration_seconds: row.duration_seconds,
      last_watched_at: row.last_watched_at
    }
  end

  # Shared tail for the two multi-leaf container kinds. They differ only
  # in which join produced `:owner_id` and how the total is counted, so
  # the grouping and summary shaping live here once.
  #
  # Totals are only counted for owners that actually have progress rows —
  # an owner with none never appears in the result map, so counting it
  # would be wasted work.
  defp summarise([], _count_totals), do: %{}

  defp summarise(rows, count_totals) do
    totals = rows |> Enum.map(& &1.owner_id) |> Enum.uniq() |> count_totals.()

    rows
    |> Enum.group_by(& &1.owner_id)
    |> Map.new(fn {owner_id, owner_rows} ->
      most_recent =
        owner_rows
        |> Enum.reject(&is_nil(&1.last_watched_at))
        |> Enum.max_by(& &1.last_watched_at, DateTime, fn -> nil end)

      {owner_id,
       %{
         current_episode: nil,
         episode_position_seconds: (most_recent && most_recent.position_seconds) || 0.0,
         episode_duration_seconds: (most_recent && most_recent.duration_seconds) || 0.0,
         episodes_completed: Enum.count(owner_rows, & &1.completed),
         episodes_total: Map.get(totals, owner_id, 0),
         last_watched_at: most_recent && most_recent.last_watched_at
       }}
    end)
  end

  defp movie_totals_by_movie_series(series_ids) do
    series_ids
    |> PresentableQueries.present_movie_counts()
    |> Repo.all()
    |> Map.new()
  end
end
