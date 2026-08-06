defmodule MediaCentaur.Library.SearchIndex do
  @moduledoc """
  The catalogue `Library.Views.Search` reads to rebuild its in-memory
  index, plus the presence set that index filters against.

  Unlike `Library.Browser`, this source is **presence-agnostic**: an
  entity appears whether or not its files are currently reachable.
  Presence is a separate answer (`presentable_entity_ids/0`), so the
  Search projection's `:present_only` filter does real work instead of
  being a tautology.

  Categorisation uses the `_by_record_count` hoist variants rather than
  the presence-based ones, so a title does not migrate between "movie"
  and "collection" just because a drive was unmounted.

  Every function here answers in a fixed number of queries — one per
  entity kind — independent of library size.
  """

  import Ecto.Query

  alias MediaCentaur.Library.{
    Episode,
    Movie,
    PlayableItem,
    PresentableQueries,
    Season,
    TVSeries,
    VideoObject,
    WatchedFile
  }

  alias MediaCentaur.Repo

  @doc """
  Returns the lightweight catalogue used by `Library.Views.Search` to
  rebuild its in-memory index.

  Unlike `Library.Browser.fetch_all_typed_entries/0`, this source is
  **presence-agnostic** — entities are included regardless of whether
  their backing files are currently reachable. Presence is computed
  per-entity by the Search projection (`Library.SearchIndex.presentable_entity_ids/0`)
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
  @spec list_all_entities() :: [map()]
  def list_all_entities do
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
end
