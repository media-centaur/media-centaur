defmodule MediaCentaur.Library.ProgressRecords do
  @moduledoc """
  Persisted watch state for the library — the database side of progress.
  Every `WatchProgress` read and write names the profile first (ADR-078).

  Two tables live here because the library has two kinds of watchable
  thing:

    * `WatchProgress`, keyed by `(profile_id, playable_item_id)`, for the
      playable leaves (Movie / Episode / VideoObject).
    * `ExtraProgress`, keyed by `(profile_id, extra_id)`, for bonus
      features, which are not `PlayableItem`s.

  They are deliberately adjacent. The two carry the *same seven
  operations* and differ only in their key, and that duplication is a
  standing convergence point — it resolves when `Extra` becomes a
  `PlayableItem`, not before. Keeping them in one module makes the
  parallel visible rather than filing it 200 lines apart.

  `mark_completed/2` and `mark_incomplete/1` already dispatch on the
  struct, so callers holding either kind of record use one name. Note
  the asymmetry in the adjacent clauses: completing a `WatchProgress`
  broadcasts `{:entity_watch_completed, record, actor}`, completing an
  `ExtraProgress` does not — extras do not participate in Continue
  Watching.

  A row holds two facts, and each has one writer here. The watched mark
  (`completed`) is set by `finish/3` (playback reached the end) or by the
  watched control (`toggle_watched/3`, `mark_completed/2`) and cleared by
  the control (`mark_incomplete/1`). The viewing in flight is written by
  the progress worker's flush (`upsert_by_profile_item!/1`), which never
  touches the mark, and ended by a finish or either control. Only
  `finish/3` moves the `SeriesWatchPosition`.

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

  @viewing_minimum_seconds 60

  @doc """
  Whether a progress record holds a viewing in flight that counts: an
  offset of at least #{@viewing_minimum_seconds} seconds. The one predicate
  the title-progress rule, the episode rows, auto-play and Continue
  Watching share — a shorter click changes nothing.
  """
  @spec viewing?(map() | nil) :: boolean()
  def viewing?(%{position_seconds: position}) when is_number(position),
    do: position >= @viewing_minimum_seconds

  def viewing?(_record), do: false

  @doc """
  Maps a `WatchProgress` record (or `nil`) to the three-state UI atom
  used by the detail panel and the SeriesDetail view model:

  - `:current`   — a viewing that counts (`viewing?/1`), whatever the watched mark
  - `:watched`   — `completed: true` with no viewing in flight
  - `:unwatched` — no progress, or an offset too short to count and not completed

  Shared between the rendering layer (`DetailPanel`) and the
  composition layer (`SeriesDetail`) so the rule lives in one place.
  """
  @spec state_from_progress(map() | nil) :: :unwatched | :current | :watched
  def state_from_progress(nil), do: :unwatched

  def state_from_progress(progress) do
    cond do
      viewing?(progress) -> :current
      progress.completed -> :watched
      true -> :unwatched
    end
  end

  alias MediaCentaur.Library.{
    Episode,
    Episodes,
    ExternalId,
    ExtraProgress,
    Movie,
    MovieOrder,
    PlayableItem,
    PlayableItems,
    PresentableQueries,
    Progress,
    Season,
    SeriesWatchPositions,
    TitleProgress,
    TVSeries,
    WatchProgress,
    Writes
  }

  alias MediaCentaur.{Repo, Topics}
  alias MediaCentaur.Profiles.Actor

  @type container_type :: :tv_series | :movie_series | :movie | :video_object

  # ---- shared lifecycle (struct-dispatched) --------------------------------

  @doc """
  The Mark watched control: sets the watched mark and clears any viewing
  in flight — in memory first (`Library.Progress.clear_viewing/2`, so no
  pending flush writes the offset back), then the persisted offset —
  leaving `last_watched_at` and the series watch position alone. `actor` is the profile that marked it, or `nil` when no person
  did; a completion is shared with friends only for an actor (ADR-082).

  A `WatchProgress` transitioning to completed broadcasts
  `{:entity_watch_completed, record, actor}` so Continue Watching and the
  watch history react; marking an already-marked record does not
  re-broadcast. `ExtraProgress` never broadcasts. Playback reaching the
  end is `finish/3`, not this.
  """
  @spec mark_completed(WatchProgress.t() | ExtraProgress.t(), Actor.t() | nil) ::
          {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def mark_completed(%WatchProgress{} = progress, actor) do
    transitioning? = not progress.completed
    :ok = Progress.clear_viewing(progress.profile_id, progress.playable_item_id)

    with {:ok, updated} <- Repo.update(WatchProgress.mark_completed_changeset(progress)) do
      if transitioning?, do: publish_completed(updated, actor)
      {:ok, updated}
    end
  end

  def mark_completed(%ExtraProgress{} = progress, _actor) do
    Repo.update(ExtraProgress.mark_completed_changeset(progress))
  end

  @doc "As `mark_completed/2`, raising on a rejected changeset."
  @spec mark_completed!(WatchProgress.t() | ExtraProgress.t(), Actor.t() | nil) :: struct()
  def mark_completed!(progress, actor), do: Repo.bang!(mark_completed(progress, actor))

  @doc """
  The Mark unwatched control: clears the watched mark and any viewing in
  flight (in memory and persisted, as `mark_completed/2`), leaving
  `last_watched_at` and the series watch position alone.
  """
  @spec mark_incomplete(WatchProgress.t() | ExtraProgress.t()) ::
          {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def mark_incomplete(%WatchProgress{} = progress) do
    :ok = Progress.clear_viewing(progress.profile_id, progress.playable_item_id)
    Repo.update(WatchProgress.mark_incomplete_changeset(progress))
  end

  def mark_incomplete(%ExtraProgress{} = progress),
    do: Repo.update(ExtraProgress.mark_incomplete_changeset(progress))

  @doc "As `mark_incomplete/1`, raising on a rejected changeset."
  @spec mark_incomplete!(WatchProgress.t() | ExtraProgress.t()) :: struct()
  def mark_incomplete!(progress), do: Repo.bang!(mark_incomplete(progress))

  @doc """
  Playback finished the item: sets the watched mark, ends the viewing and,
  for an item of a series, moves the profile's
  `MediaCentaur.Library.SeriesWatchPosition` there — one transaction.
  Always publishes `{:entity_watch_completed, record, actor}`: a second
  finish of the same item is a second completion.
  """
  @spec finish(WatchProgress.t(), number(), Actor.t()) :: {:ok, WatchProgress.t()} | {:error, term()}
  def finish(%WatchProgress{} = progress, duration_seconds, %Actor{} = actor) do
    result =
      Repo.transact(fn ->
        with {:ok, updated} <- Repo.update(WatchProgress.finish_changeset(progress, duration_seconds)),
             :ok <- move_series_position(updated) do
          {:ok, updated}
        end
      end)

    with {:ok, updated} <- result do
      publish_completed(updated, actor)
      {:ok, updated}
    end
  end

  defp move_series_position(progress) do
    case SeriesWatchPositions.record_finish(
           progress.profile_id,
           progress.playable_item_id,
           progress.last_watched_at
         ) do
      :none -> :ok
      {:ok, _position} -> :ok
      {:error, _changeset} = error -> error
    end
  end

  defp publish_completed(progress, actor),
    do: Topics.publish(Topics.library_watch_completed(), {:entity_watch_completed, progress, actor})

  @doc "Playback finished an extra: the mark is set and the viewing is over. Extras publish nothing."
  @spec finish_extra(ExtraProgress.t(), number()) ::
          {:ok, ExtraProgress.t()} | {:error, Ecto.Changeset.t()}
  def finish_extra(%ExtraProgress{} = progress, duration_seconds),
    do: Repo.update(ExtraProgress.finish_changeset(progress, duration_seconds))

  # ---- the watched control -------------------------------------------------

  @doc """
  Which watched control a record offers: Mark watched while it is unmarked
  or has a viewing that counts (`viewing?/1`), else Mark unwatched. A
  watched item with an abandoned viewing is thereby dismissable without
  losing its mark.
  """
  @spec watched_control(map() | nil) :: :mark_watched | :mark_unwatched
  def watched_control(%{completed: true} = progress),
    do: if(viewing?(progress), do: :mark_watched, else: :mark_unwatched)

  def watched_control(_progress), do: :mark_watched

  @doc """
  Applies the watched control a leaf container offers (`watched_control/1`)
  for the actor's profile. The control is read from the record at its live
  offset (`Library.Progress.overlay_in_memory/1`), the record
  `title_progress/2` hands the page, so the control applied is the one
  shown: a watched item being replayed is offered Mark watched, and the
  press keeps its mark.
  """
  @spec toggle_watched(Actor.t(), PlayableItem.container_type(), Ecto.UUID.t()) ::
          {:ok, WatchProgress.t()} | {:error, term()}
  def toggle_watched(%Actor{} = actor, container_type, container_id) when is_binary(container_id) do
    profile_id = actor.profile_id

    progress =
      case fetch_for_container(profile_id, container_type, container_id) do
        {:ok, record} -> record
        {:error, :not_found} -> nil
      end

    apply_watched_control(progress, actor, fn ->
      insert_marked_for_container(actor, container_type, container_id)
    end)
  end

  @doc "As `toggle_watched/3`, for an extra of `entity_id`."
  @spec toggle_extra_watched(Actor.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, ExtraProgress.t()} | {:error, term()}
  def toggle_extra_watched(%Actor{} = actor, _entity_id, extra_id) do
    profile_id = actor.profile_id

    progress =
      case fetch_for_extra(profile_id, extra_id) do
        {:ok, record} -> record
        {:error, :not_found} -> nil
      end

    apply_watched_control(progress, actor, fn ->
      Repo.insert(ExtraProgress.marked_changeset(%{profile_id: profile_id, extra_id: extra_id}))
    end)
  end

  # Marking an item that has no row inserts the mark alone
  # (`marked_changeset/1`): a hand mark is not a viewing, so the new row
  # carries no `last_watched_at`. The item may still have a viewing in
  # memory that no flush has persisted yet; it is cleared first.
  defp apply_watched_control(progress, actor, insert_marked) do
    case {watched_control(live(progress)), progress} do
      {:mark_unwatched, record} -> mark_incomplete(record)
      {:mark_watched, nil} -> insert_marked.()
      {:mark_watched, record} -> mark_completed(record, actor)
    end
  end

  # Extras have no in-memory row; only a `WatchProgress` has a live offset.
  defp live(%WatchProgress{} = progress), do: Progress.overlay_in_memory(progress)
  defp live(progress), do: progress

  defp insert_marked_for_container(actor, container_type, container_id) do
    position = PlayableItems.canonical_position(container_type, container_id)

    with {:ok, playable_item} <- PlayableItems.find_or_create(container_type, container_id, position),
         :ok <- Progress.clear_viewing(actor.profile_id, playable_item.id),
         {:ok, marked} <-
           Repo.insert(
             WatchProgress.marked_changeset(%{
               profile_id: actor.profile_id,
               playable_item_id: playable_item.id
             })
           ) do
      publish_completed(marked, actor)
      {:ok, marked}
    end
  end

  @doc """
  Seed data's watched item: the row a finish leaves — mark set, no
  viewing, duration kept — for a leaf container, whether or not the row
  exists. Publishes nothing and does not move the series watch position,
  so a seeder speaks for no one; playback is `finish/3`.
  """
  @spec seed_watched(Ecto.UUID.t(), PlayableItem.container_type(), Ecto.UUID.t(), number()) ::
          {:ok, WatchProgress.t()} | {:error, term()}
  def seed_watched(profile_id, container_type, container_id, duration_seconds) do
    with {:ok, progress} <- find_or_create_for_container(profile_id, container_type, container_id) do
      Repo.update(WatchProgress.finish_changeset(progress, duration_seconds))
    end
  end

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
  The progress worker's flush: writes one in-memory row — the viewing in
  flight, never the watched mark — through to its
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

  Used by `Library.Progress.complete/2` — a finish has to resolve the
  persisted row, creating one if necessary, before `finish/3` writes it.
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

  The rows alone; a title's progress with its derived reading is
  `title_progress/2`.

  Returns `[]` for an unknown container id, or one with no rows beneath
  any leaf.
  """
  @spec list_for_container(Ecto.UUID.t(), container_type(), Ecto.UUID.t()) :: [WatchProgress.t()]
  def list_for_container(profile_id, :tv_series, id), do: list_for_tv_series(profile_id, id)
  def list_for_container(profile_id, :movie_series, id), do: list_for_movie_series(profile_id, id)
  def list_for_container(profile_id, :movie, id), do: list_for_leaf(profile_id, :movie, id)
  def list_for_container(profile_id, :video_object, id), do: list_for_leaf(profile_id, :video_object, id)

  @doc """
  One profile's progress through a title: its item progress records, each
  at its live offset (`Library.Progress.overlay_in_memory/1`), and the
  `MediaCentaur.Library.TitleProgress` derived from them and from the
  profile's series watch position. The one place a title's progress is
  assembled — playback resolution, the progress broadcast and the detail
  view models all read it here.

  `entity` is the title's entity view; its ordered set is
  `TitleProgress.ordered_set/1`.
  """
  @spec title_progress(Ecto.UUID.t(), map()) :: %{
          title_progress: TitleProgress.t(),
          records: [WatchProgress.t()]
        }
  def title_progress(profile_id, %{id: id, type: type} = entity) when is_binary(profile_id) do
    records = profile_id |> list_for_container(type, id) |> Enum.map(&Progress.overlay_in_memory/1)
    position = if type in [:tv_series, :movie_series], do: SeriesWatchPositions.get(profile_id, id)
    %{title_progress: TitleProgress.for_entity(entity, position, records), records: records}
  end

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
  The bulk read of title progress: `%{entity_id => TitleProgress}` for
  every container id in the input under which `profile_id` has a progress
  row or a series watch position. A title with neither is absent — it is
  unstarted, and its card draws no bar.

  The same reading as `title_progress/2`, for callers holding ids and no
  entity view (the library grid, Continue Watching): the rows at their
  live offset, the series watch position, the rule. A series' ordered set
  comes from file presence in SQL here and from the entity view there;
  both are "the items with a file, in story order".

  A fixed number of queries whatever the number of ids: one for the rows
  of each kind, and for the two series kinds one for the ordered sets and
  one for the positions.
  """
  @spec title_progresses(Ecto.UUID.t(), [Ecto.UUID.t()]) :: %{Ecto.UUID.t() => TitleProgress.t()}
  def title_progresses(_profile_id, []), do: %{}

  def title_progresses(profile_id, entity_ids) when is_binary(profile_id) and is_list(entity_ids) do
    title_progresses_by_kind(profile_id, %{
      movie: entity_ids,
      video_object: entity_ids,
      movie_series: entity_ids,
      tv_series: entity_ids
    })
  end

  @doc """
  As `title_progresses/2`, for a caller that knows each id's container
  kind: only the queries of the kinds given run. Kinds with no ids cost
  nothing.
  """
  @spec title_progresses_by_kind(Ecto.UUID.t(), %{optional(container_type()) => [Ecto.UUID.t()]}) ::
          %{Ecto.UUID.t() => TitleProgress.t()}
  def title_progresses_by_kind(profile_id, ids_by_kind) when is_binary(profile_id) do
    Enum.reduce(ids_by_kind, %{}, fn {kind, ids}, progresses ->
      Map.merge(progresses, kind_progresses(profile_id, kind, ids))
    end)
  end

  @doc """
  When `profile_id` last watched each title in `entity_ids`: the newest
  `last_watched_at` among the rows beneath it, as `%{entity_id =>
  DateTime}`. A title with no dated row — untouched, or only marked by
  hand — is absent.

  A different fact from title progress, whose `last_watched_at` speaks of
  the place in a title and is empty for a finished movie: this one is
  "when was this last on screen", which the Library's Recently Watched
  order reads. One aggregate query per container kind.
  """
  @spec last_watched_at_by_title(Ecto.UUID.t(), [Ecto.UUID.t()]) :: %{Ecto.UUID.t() => DateTime.t()}
  def last_watched_at_by_title(_profile_id, []), do: %{}

  def last_watched_at_by_title(profile_id, entity_ids)
      when is_binary(profile_id) and is_list(entity_ids) do
    leaves =
      for kind <- [:movie, :video_object] do
        from([wp, pi] in exclude(leaf_rows(profile_id, kind, entity_ids), :select),
          group_by: pi.container_id,
          select: {pi.container_id, type(max(wp.last_watched_at), :utc_datetime)}
        )
      end

    tv_series =
      from(
        [wp, _pi, _episode, season] in exclude(
          episode_rows_by_tv_series(profile_id, entity_ids),
          :select
        ),
        group_by: season.tv_series_id,
        select: {season.tv_series_id, type(max(wp.last_watched_at), :utc_datetime)}
      )

    movie_series =
      from([wp, _pi, movie] in exclude(movie_rows_by_movie_series(profile_id, entity_ids), :select),
        group_by: movie.movie_series_id,
        select: {movie.movie_series_id, type(max(wp.last_watched_at), :utc_datetime)}
      )

    for query <- [tv_series, movie_series | leaves],
        {entity_id, %DateTime{} = last_watched_at} <- Repo.all(query),
        into: %{},
        do: {entity_id, last_watched_at}
  end

  @doc "The shortest offset, in seconds, at which a viewing counts (`viewing?/1`), for a query to filter on."
  @spec viewing_minimum_seconds() :: pos_integer()
  def viewing_minimum_seconds, do: @viewing_minimum_seconds

  @doc "Every profile with at least one progress row — the profiles Continue Watching is built for."
  @spec profile_ids_with_progress() :: [Ecto.UUID.t()]
  def profile_ids_with_progress,
    do:
      Repo.all(from(wp in WatchProgress, distinct: true, select: wp.profile_id, order_by: wp.profile_id))

  # ---- ExtraProgress -------------------------------------------------------

  @doc "Fetches one profile's progress row for an Extra."
  @spec fetch_for_extra(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, ExtraProgress.t()} | {:error, :not_found}
  def fetch_for_extra(profile_id, extra_id) when is_binary(profile_id) and is_binary(extra_id) do
    case Repo.get_by(ExtraProgress, profile_id: profile_id, extra_id: extra_id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @doc "Upserts one profile's progress on an extra; `attrs` carries `:profile_id` and `:extra_id`."
  @spec find_or_create_for_extra(map()) ::
          {:ok, ExtraProgress.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create_for_extra(attrs) do
    Writes.upsert_by(
      ExtraProgress,
      [profile_id: Writes.attr(attrs, :profile_id), extra_id: Writes.attr(attrs, :extra_id)],
      attrs
    )
  end

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
  @doc """
  The series `profile_id` has finished at least one episode of, each with
  a TMDB identity, as the map `Title.Logic.snapshot_from_entity/1` reads:
  `id`, `type: :tv_series`, `tmdb_id` (the stored string), `name`,
  `date_published` and `description`. A series without a TMDB identity
  has no title to act on and is left out. Ordered by name.
  """
  @spec watched_tv_series(String.t()) :: [map()]
  def watched_tv_series(profile_id) when is_binary(profile_id) do
    watched_ids =
      from(wp in WatchProgress,
        join: pi in PlayableItem,
        on: pi.id == wp.playable_item_id and pi.container_type == :episode,
        join: e in Episode,
        on: e.id == pi.container_id,
        join: s in Season,
        on: s.id == e.season_id,
        where: wp.profile_id == ^profile_id and wp.completed,
        select: s.tv_series_id
      )

    Repo.all(
      from(t in TVSeries,
        join: x in ExternalId,
        on: x.owner_id == t.id and x.owner_type == :tv_series and x.source == "tmdb",
        where: t.id in subquery(watched_ids),
        order_by: [asc: t.name, asc: t.id],
        select: %{
          id: t.id,
          type: :tv_series,
          tmdb_id: x.external_id,
          name: t.name,
          date_published: t.date_published,
          description: t.description
        }
      )
    )
  end

  @doc """
  The latest regular episode (season 1 or later) `profile_id` has
  finished of the library series carrying TMDB id `tmdb_id`, as
  `{season, episode}`, or nil when the profile has finished none — the
  evidence `ReleaseTracking.set_rung/4` starts a followed series' point
  from.
  """
  @spec last_watched_episode(String.t(), integer()) :: {pos_integer(), pos_integer()} | nil
  def last_watched_episode(profile_id, tmdb_id) when is_binary(profile_id) and is_integer(tmdb_id) do
    external_id = Integer.to_string(tmdb_id)

    Repo.one(
      from(wp in WatchProgress,
        join: pi in PlayableItem,
        on: pi.id == wp.playable_item_id and pi.container_type == :episode,
        join: e in Episode,
        on: e.id == pi.container_id,
        join: s in Season,
        on: s.id == e.season_id,
        join: x in ExternalId,
        on: x.owner_id == s.tv_series_id and x.owner_type == :tv_series and x.source == "tmdb",
        where: wp.profile_id == ^profile_id and wp.completed and x.external_id == ^external_id,
        where: s.season_number >= 1,
        order_by: [desc: s.season_number, desc: e.episode_number],
        limit: 1,
        select: {s.season_number, e.episode_number}
      )
    )
  end

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

  defp kind_progresses(_profile_id, _kind, []), do: %{}

  # A movie or video object is its own one-item ordered set and has no
  # series watch position. Presence-agnostic, as Continue Watching is: an
  # absent file does not erase a viewing.
  defp kind_progresses(profile_id, kind, ids) when kind in [:movie, :video_object] do
    profile_id
    |> leaf_rows(kind, ids)
    |> Repo.all()
    |> Map.new(fn {container_id, row} ->
      row = row |> attach_leaf(kind, container_id) |> Progress.overlay_in_memory()
      {container_id, TitleProgress.compute([%{id: container_id, key: []}], nil, [row])}
    end)
  end

  defp kind_progresses(profile_id, :tv_series, ids) do
    rows =
      profile_id
      |> episode_rows_by_tv_series(ids)
      |> Repo.all()
      |> Enum.map(fn {series_id, episode_id, row} ->
        {series_id, attach_leaf(row, :episode, episode_id)}
      end)

    series_progresses(profile_id, rows, Episodes.ordered_items_by_tv_series(ids))
  end

  defp kind_progresses(profile_id, :movie_series, ids) do
    rows =
      profile_id
      |> movie_rows_by_movie_series(ids)
      |> Repo.all()
      |> Enum.map(fn {series_id, movie_id, row} -> {series_id, attach_leaf(row, :movie, movie_id)} end)

    series_progresses(profile_id, rows, ordered_items_by_movie_series(ids))
  end

  # `rows` are `{series_id, row}`; `ordered` is `%{series_id => [%{id, key}]}`.
  # A series with no rows and no position is left out: nothing was started.
  defp series_progresses(profile_id, rows, ordered) do
    positions = SeriesWatchPositions.by_series(profile_id, Map.keys(ordered))

    rows_by_series =
      Enum.group_by(rows, &elem(&1, 0), fn {_series_id, row} -> Progress.overlay_in_memory(row) end)

    ordered
    |> Enum.map(fn {series_id, items} ->
      {series_id, items, positions[series_id], Map.get(rows_by_series, series_id, [])}
    end)
    |> Enum.reject(fn {_series_id, _items, position, series_rows} ->
      position == nil and series_rows == []
    end)
    |> Map.new(fn {series_id, items, position, series_rows} ->
      {series_id, TitleProgress.compute(items, position, series_rows)}
    end)
  end

  # Each collection's ordered set — its movies with a file, in story order,
  # with their order keys — in one query; the collection twin of
  # `Episodes.ordered_items_by_tv_series/1`.
  defp ordered_items_by_movie_series(series_ids) do
    from(movie in PresentableQueries.present_movies(),
      where: movie.movie_series_id in ^series_ids,
      select: %{
        id: movie.id,
        movie_series_id: movie.movie_series_id,
        date_published: movie.date_published,
        position: movie.position
      }
    )
    |> Repo.all()
    |> Enum.group_by(& &1.movie_series_id)
    |> Map.new(fn {series_id, movies} ->
      {series_id,
       movies |> MovieOrder.sort_movies() |> Enum.map(&%{id: &1.id, key: MovieOrder.order_key(&1)})}
    end)
  end
end
