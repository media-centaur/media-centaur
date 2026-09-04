defmodule MediaCentaur.Library.ProgressRecords do
  @moduledoc """
  Persisted watch state for the library — the database side of progress.

  Two tables live here because the library has two kinds of watchable
  thing:

    * `WatchProgress`, keyed by `playable_item_id`, for the playable
      leaves (Movie / Episode / VideoObject).
    * `ExtraProgress`, keyed by `extra_id`, for bonus features, which are
      not `PlayableItem`s.

  They are deliberately adjacent. The two carry the *same seven
  operations* and differ only in their key, and that duplication is a
  standing convergence point — it resolves when `Extra` becomes a
  `PlayableItem`, not before. Keeping them in one module makes the
  parallel visible rather than filing it 200 lines apart.

  `mark_completed/1`, `mark_incomplete/1` and `destroy/1` already
  dispatch on the struct, so callers holding either kind of record use
  one name. Note the asymmetry in the adjacent clauses:
  completing a `WatchProgress` broadcasts `{:entity_watch_completed,
  record}`, completing an `ExtraProgress` does not — extras do not
  participate in Continue Watching.

  Not to be confused with `Library.Progress`, which is the in-memory ETS
  projection that debounce-flushes *into* this module.
  """

  import Ecto.Query

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

  @doc "Deletes a progress record."
  @spec destroy(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def destroy(progress), do: Repo.delete(progress)

  @doc "As `destroy/1`, raising on failure and returning `:ok`."
  @spec destroy!(struct()) :: :ok
  def destroy!(progress), do: Writes.destroy!(progress)

  # ---- WatchProgress -------------------------------------------------------

  @doc "Every `WatchProgress` row."
  @spec list_all() :: [WatchProgress.t()]
  def list_all, do: Repo.all(WatchProgress)

  @doc """
  Fetches the watch-progress row for a leaf container, resolving through
  its `PlayableItem`.
  """
  @spec fetch_for_container(PlayableItem.container_type(), Ecto.UUID.t()) ::
          {:ok, WatchProgress.t()} | {:error, :not_found}
  def fetch_for_container(container_type, container_id) do
    query =
      from(wp in WatchProgress,
        join: pi in PlayableItem,
        on: pi.id == wp.playable_item_id,
        where: pi.container_type == ^container_type and pi.container_id == ^container_id,
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @doc """
  Upserts the watch-progress row for a leaf container, resolving (and
  creating if needed) its canonical `PlayableItem` first.

  The position is derived by `PlayableItems.canonical_position/2` — the
  only per-type behaviour in this path.
  """
  @spec find_or_create_for_container(PlayableItem.container_type(), Ecto.UUID.t(), map()) ::
          {:ok, WatchProgress.t()} | {:error, term()}
  def find_or_create_for_container(container_type, container_id, attrs \\ %{}) do
    position = PlayableItems.canonical_position(container_type, container_id)

    with {:ok, playable_item} <-
           PlayableItems.find_or_create(container_type, container_id, position) do
      attrs =
        attrs
        |> Map.new()
        |> Map.put(:playable_item_id, playable_item.id)

      Writes.upsert_by(WatchProgress, [playable_item_id: playable_item.id], attrs)
    end
  end

  @doc """
  Upserts a `WatchProgress` row by `playable_item_id`, raising on
  failure.

  Used by `Library.Progress.Worker` during the debounced flush — the
  in-memory row already carries the canonical `playable_item_id`, so it
  bypasses the container-shaped path above. A flush error means the
  in-memory row is out of sync with the DB and must surface immediately
  rather than silently dropping state.
  """
  @spec upsert_by_playable_item!(map()) :: WatchProgress.t()
  def upsert_by_playable_item!(%{playable_item_id: playable_item_id} = attrs)
      when is_binary(playable_item_id) do
    case Writes.upsert_by(WatchProgress, [playable_item_id: playable_item_id], attrs) do
      {:ok, record} -> record
      {:error, changeset} -> raise "WatchProgress flush failed: #{inspect(changeset)}"
    end
  end

  @doc """
  Looks up or creates the `WatchProgress` row for a `playable_item_id`.

  Used by `Library.Progress.complete/1` — completion has to resolve the
  persisted row, creating one if necessary, before flipping `completed`.
  """
  @spec find_or_create_by_playable_item(Ecto.UUID.t()) ::
          {:ok, WatchProgress.t()} | {:error, term()}
  def find_or_create_by_playable_item(playable_item_id) when is_binary(playable_item_id) do
    case Repo.get_by(WatchProgress, playable_item_id: playable_item_id) do
      nil ->
        Writes.upsert_by(WatchProgress, [playable_item_id: playable_item_id], %{
          playable_item_id: playable_item_id
        })

      record ->
        {:ok, record}
    end
  end

  @doc """
  Every `WatchProgress` record beneath a container, each carrying a
  synthesised `:playable_item` map (`container_type` + `container_id`)
  so consumers can key by leaf-container UUID without a separate
  `belongs_to :playable_item` preload.

  Same shape `EntityShape.extract_progress/2` produces from a preloaded
  record; this is the projection-side counterpart, used by the modal
  compose flows where there is no preloaded entity to extract from.

  Returns `[]` for an unknown container id, or one with no rows beneath
  any leaf.
  """
  @spec list_for_container(container_type(), Ecto.UUID.t()) :: [struct()]
  def list_for_container(:tv_series, id), do: list_for_tv_series(id)
  def list_for_container(:movie_series, id), do: list_for_movie_series(id)
  def list_for_container(:movie, id), do: list_for_leaf(:movie, id)
  def list_for_container(:video_object, id), do: list_for_leaf(:video_object, id)

  @doc """
  TV-series specialisation of `list_for_container/2`, kept for the
  `SeriesDetail.compose` call site that preceded the unified dispatcher.
  """
  @spec list_for_tv_series(Ecto.UUID.t()) :: [struct()]
  def list_for_tv_series(tv_series_id) when is_binary(tv_series_id) do
    from(wp in WatchProgress,
      join: pi in PlayableItem,
      on: pi.id == wp.playable_item_id and pi.container_type == :episode,
      join: e in Episode,
      on: e.id == pi.container_id,
      join: s in Season,
      on: s.id == e.season_id,
      where: s.tv_series_id == ^tv_series_id,
      select: {wp, e.id}
    )
    |> Repo.all()
    |> Enum.map(fn {progress, episode_id} ->
      %{progress | playable_item: %{container_type: :episode, container_id: episode_id}}
    end)
  end

  @doc """
  Bulk progress lookup for projection consumers (Phase 3.1). Resolves
  `%{entity_id => summary}` for every container UUID in the input that
  has at least one `WatchProgress` row.

  Each summary carries the shape `Library.ProgressSummary.compute/2`
  returns, plus `:last_watched_at` so consumers that sort by recency
  don't need a separate progress preload. Entities with no progress rows
  are absent from the result (not set to `nil`). Worst case one query
  per container kind in the input set; totals do not scale with row
  count.
  """
  @spec summaries([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => summary()}
  def summaries([]), do: %{}

  def summaries(entity_ids) when is_list(entity_ids) do
    %{}
    |> Map.merge(leaf_summaries(:movie, entity_ids))
    |> Map.merge(leaf_summaries(:video_object, entity_ids))
    |> Map.merge(movie_series_summaries(entity_ids))
    |> Map.merge(tv_series_summaries(entity_ids))
  end

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

  defp list_for_movie_series(movie_series_id) when is_binary(movie_series_id) do
    from(wp in WatchProgress,
      join: pi in PlayableItem,
      on: pi.id == wp.playable_item_id and pi.container_type == :movie,
      join: m in Movie,
      on: m.id == pi.container_id,
      where: m.movie_series_id == ^movie_series_id,
      select: {wp, m.id}
    )
    |> Repo.all()
    |> Enum.map(fn {progress, movie_id} ->
      %{progress | playable_item: %{container_type: :movie, container_id: movie_id}}
    end)
  end

  defp list_for_leaf(container_type, container_id) when is_binary(container_id) do
    from(wp in WatchProgress,
      join: pi in PlayableItem,
      on:
        pi.id == wp.playable_item_id and pi.container_type == ^container_type and
          pi.container_id == ^container_id,
      select: wp
    )
    |> Repo.all()
    |> Enum.map(fn progress ->
      %{progress | playable_item: %{container_type: container_type, container_id: container_id}}
    end)
  end

  # Movies and video objects are single-leaf containers — totals are
  # always 1, so no separate count query is needed.
  defp leaf_summaries(container_type, ids) do
    rows =
      Repo.all(
        from(wp in WatchProgress,
          join: pi in PlayableItem,
          on:
            pi.id == wp.playable_item_id and pi.container_type == ^container_type and
              pi.container_id in ^ids,
          select: %{
            container_id: pi.container_id,
            position_seconds: wp.position_seconds,
            duration_seconds: wp.duration_seconds,
            completed: wp.completed,
            last_watched_at: wp.last_watched_at
          }
        )
      )

    Map.new(rows, fn row ->
      {row.container_id,
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
  defp tv_series_summaries(ids) do
    rows =
      Repo.all(
        from(wp in WatchProgress,
          join: pi in PlayableItem,
          on: pi.id == wp.playable_item_id and pi.container_type == :episode,
          join: e in Episode,
          on: e.id == pi.container_id,
          join: s in Season,
          on: s.id == e.season_id,
          where: s.tv_series_id in ^ids,
          select: %{
            owner_id: s.tv_series_id,
            completed: wp.completed,
            position_seconds: wp.position_seconds,
            duration_seconds: wp.duration_seconds,
            last_watched_at: wp.last_watched_at
          }
        )
      )

    summarise(rows, &Episodes.count_available_by_tv_series/1)
  end

  # Movie series: total counts *present* child movies (those with a
  # WatchedFile); completed counts child movies carrying a completed
  # WatchProgress.
  defp movie_series_summaries(ids) do
    rows =
      Repo.all(
        from(wp in WatchProgress,
          join: pi in PlayableItem,
          on: pi.id == wp.playable_item_id and pi.container_type == :movie,
          join: m in Movie,
          on: m.id == pi.container_id,
          where: m.movie_series_id in ^ids,
          select: %{
            owner_id: m.movie_series_id,
            completed: wp.completed,
            position_seconds: wp.position_seconds,
            duration_seconds: wp.duration_seconds,
            last_watched_at: wp.last_watched_at
          }
        )
      )

    summarise(rows, &movie_totals_by_movie_series/1)
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
