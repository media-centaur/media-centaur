defmodule MediaCentarr.Library.Views.Search do
  @moduledoc """
  ETS-backed in-memory search index over the library (ADR-041,
  Library Schema v2 Phase 3 Task C).

  Replaces ad-hoc `where ilike` queries with a sub-10ms in-memory scan
  for libraries up to ~10K entries. The scoring function lives in
  `MediaCentarr.Library.Views.Search.Scorer` and is unit-tested
  independently (`async: true`).

  ## What gets indexed

  One row per top-level entity from `Library.list_all_entities_for_search/0`,
  which is **presence-agnostic** — entities are indexed regardless of
  whether their backing files are currently reachable. The
  `:present_only` read option then does real work, filtering against
  the honest `present?` flag computed at refresh time
  (`Library.presentable_entity_ids/0`).

  Indexed kinds:

    * Standalone Movies and singleton-collection-hoisted Movies
      (`container_type: :movie`)
    * TVSeries (`container_type: :tv_series`)
    * MovieSeries with 2+ child Movie records
      (`container_type: :movie_series`)
    * VideoObjects (`container_type: :video_object`)

  Each row carries a representative `playable_item_id` for `Play`
  semantics. For containers that own multiple PlayableItems (TVSeries
  episodes, MovieSeries children), the first leaf is chosen
  deterministically (lowest position / first episode in the first
  season). For containers without any PlayableItem the entity is
  skipped — there is nothing to play.

  ## Storage

    * `:library_view_search` — `:set`, `:public`, `:named_table`,
      `:read_concurrency, true`.
    * Row shape: `{playable_item_id, {normalised_name, %SearchItem{}}}`.
      The nested tuple keeps the per-row inputs the scorer needs
      (`normalised_name`) co-located with the view-model struct
      returned to consumers (`%SearchItem{}`). The struct already
      carries `:present?`, `:container_type`, `:container_id`, etc., so
      the filters apply directly without re-reading the underlying
      record.
    * Refreshes replace every row in a single `:ets.delete_all_objects`
      + `:ets.insert` pair. Concurrent readers see either the previous
      snapshot or the new one, never a partial state.

  ## Refresh strategy

  Full rebuild on every relevant event. The projection is small and
  rebuild cost is bounded; partial refresh isn't worth the complexity
  here (cf. `Library.Views.Detail`, which keys per-PlayableItem and
  benefits from targeted rebuilds).

  ## Refresh triggers

    * `library:updates` — entity creates / edits / deletes
      (coalesced upstream by `Library.BroadcastCoalescer`).
    * `library:availability` — drive-mount / drive-unmount events.
      The source query is presence-agnostic, but `present?` per row is
      recomputed at refresh time from `Library.presentable_entity_ids/0`,
      so a presence flip changes which rows pass `:present_only`.

  ## Broadcast contract

  Emits `{:library_view_updated, :search}` on the `library:views` topic
  after every successful refresh. Consumers subscribe to the derived
  topic and re-read on demand.
  """
  @behaviour MediaCentarr.Cache

  alias MediaCentarr.Library
  alias MediaCentarr.Library.Availability
  alias MediaCentarr.Library.Views.Search.Scorer
  alias MediaCentarr.Library.Views.SearchItem
  alias MediaCentarr.Topics

  @table :library_view_search
  @default_limit 50

  @impl MediaCentarr.Cache
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_updates())
    Availability.subscribe()
    :ok
  end

  @impl MediaCentarr.Cache
  def relevant?({:entities_changed, _}), do: true
  def relevant?({:availability_changed, _dir, _state}), do: true
  def relevant?(_), do: false

  @impl MediaCentarr.Cache
  def refresh_cache do
    ensure_table()

    rows = build_rows()

    :ets.delete_all_objects(@table)
    :ets.insert(@table, rows)

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.library_views(),
      {:library_view_updated, :search}
    )

    :ok
  end

  @doc """
  Read the projection for `query`. Returns up to `opts[:limit]`
  `SearchItem` structs sorted by descending score, then ascending name.

  Options:

    * `:limit`        — non-negative integer; defaults to #{@default_limit}.
    * `:kind_filter`  — `:all | :movies | :tv_series | :movie_series | :video_objects`;
                        defaults to `:all`.
    * `:present_only` — boolean; defaults to `false`. When `true`,
                        excludes entries whose backing files aren't
                        currently reachable.

  Falls back to a live build when the ETS table is absent — covers test
  mode (Cache.Worker not started) and the brief window between boot
  and first refresh.
  """
  @spec read(String.t(), keyword()) :: [SearchItem.t()]
  def read(query, opts \\ [])

  def read(query, _opts) when not is_binary(query), do: []

  def read(query, opts) do
    case normalise(query) do
      "" ->
        []

      normalised_query ->
        limit = Keyword.get(opts, :limit, @default_limit)
        kind_filter = Keyword.get(opts, :kind_filter, :all)
        present_only = Keyword.get(opts, :present_only, false)

        rows = stored_rows()

        rows
        |> Enum.flat_map(&score_row(&1, normalised_query))
        |> Enum.filter(&matches_filters?(&1, kind_filter, present_only))
        |> Enum.sort_by(fn item -> {-item.score, item.name} end)
        |> Enum.take(limit)
    end
  end

  # --- Row source ---

  defp stored_rows do
    case :ets.whereis(@table) do
      :undefined -> build_rows()
      _ref -> :ets.tab2list(@table)
    end
  end

  defp build_rows do
    entities = Library.list_all_entities_for_search()

    # Bulk-resolve representative PlayableItem ids per (container_type,
    # container_id). One query per distinct container kind, regardless of
    # entity count.
    leaf_pairs = leaf_container_pairs(entities)
    leaf_pi_ids = Library.representative_playable_item_ids_by_container(leaf_pairs)

    # Bulk-resolve presence at the leaf level. The set holds
    # `{container_type, container_id}` pairs for which at least one
    # WatchedFile is currently present.
    presence_set = Library.presentable_entity_ids()

    Enum.flat_map(entities, fn entity ->
      case canonical_leaf_pair(entity, leaf_pi_ids) do
        nil ->
          []

        {_leaf_pair, playable_item_id} ->
          name = entity.name || ""
          normalised_name = normalise(name)

          present? = entity_present?(entity, presence_set)

          item = %SearchItem{
            playable_item_id: playable_item_id,
            container_type: entity.type,
            container_id: entity.id,
            name: name,
            year: year_from(entity.date_published),
            score: nil,
            present?: present?
          }

          [{playable_item_id, {normalised_name, item}}]
      end
    end)
  end

  # --- Bulk-lookup helpers ---

  # Collect every (container_type, container_id) the bulk PlayableItem
  # lookup needs to resolve. For TVSeries / MovieSeries the canonical
  # leaf lives at the child level (:episode / :movie); the search row
  # is keyed at the container level but the play target is one of its
  # children.
  defp leaf_container_pairs(entities) do
    entities
    |> Enum.flat_map(&leaf_pairs_for_entity/1)
    |> Enum.uniq()
  end

  defp leaf_pairs_for_entity(%{type: :movie, id: id}), do: [{:movie, id}]
  defp leaf_pairs_for_entity(%{type: :video_object, id: id}), do: [{:video_object, id}]

  defp leaf_pairs_for_entity(%{type: :tv_series, episode_ids: episode_ids}) when is_list(episode_ids) do
    Enum.map(episode_ids, fn ep_id -> {:episode, ep_id} end)
  end

  defp leaf_pairs_for_entity(%{type: :movie_series, movie_ids: movie_ids}) when is_list(movie_ids) do
    Enum.map(movie_ids, fn m_id -> {:movie, m_id} end)
  end

  defp leaf_pairs_for_entity(_), do: []

  # Pick the canonical leaf (first child in play order) that actually
  # has a PlayableItem. Returns `{{leaf_type, leaf_id}, playable_item_id}`
  # or nil if no child has one.
  defp canonical_leaf_pair(%{type: :movie, id: id}, leaf_pi_ids) do
    leaf_pi_for({:movie, id}, leaf_pi_ids)
  end

  defp canonical_leaf_pair(%{type: :video_object, id: id}, leaf_pi_ids) do
    leaf_pi_for({:video_object, id}, leaf_pi_ids)
  end

  defp canonical_leaf_pair(%{type: :tv_series, episode_ids: ids}, leaf_pi_ids) when is_list(ids) do
    Enum.find_value(ids, fn ep_id -> leaf_pi_for({:episode, ep_id}, leaf_pi_ids) end)
  end

  defp canonical_leaf_pair(%{type: :movie_series, movie_ids: ids}, leaf_pi_ids) when is_list(ids) do
    Enum.find_value(ids, fn m_id -> leaf_pi_for({:movie, m_id}, leaf_pi_ids) end)
  end

  defp canonical_leaf_pair(_entity, _leaf_pi_ids), do: nil

  defp leaf_pi_for(pair, leaf_pi_ids) do
    case Map.fetch(leaf_pi_ids, pair) do
      {:ok, pi_id} -> {pair, pi_id}
      :error -> nil
    end
  end

  # An entity is `present?` when any of its leaves is present. For
  # single-leaf containers (Movie / VideoObject) this is just the
  # leaf's own membership in the presence set; for TVSeries /
  # MovieSeries we OR across the child IDs.
  defp entity_present?(%{type: :movie, id: id}, presence_set) do
    MapSet.member?(presence_set, {:movie, id})
  end

  defp entity_present?(%{type: :video_object, id: id}, presence_set) do
    MapSet.member?(presence_set, {:video_object, id})
  end

  defp entity_present?(%{type: :tv_series, episode_ids: ids}, presence_set) when is_list(ids) do
    Enum.any?(ids, fn ep_id -> MapSet.member?(presence_set, {:episode, ep_id}) end)
  end

  defp entity_present?(%{type: :movie_series, movie_ids: ids}, presence_set) when is_list(ids) do
    Enum.any?(ids, fn m_id -> MapSet.member?(presence_set, {:movie, m_id}) end)
  end

  defp entity_present?(_entity, _presence_set), do: false

  # --- Scoring + filtering ---

  defp score_row({_playable_item_id, {normalised_name, %SearchItem{} = item}}, normalised_query) do
    case Scorer.score(normalised_query, normalised_name) do
      score when score > 0.0 -> [%{item | score: score}]
      _ -> []
    end
  end

  defp matches_filters?(item, kind_filter, present_only) do
    kind_matches?(item, kind_filter) and presence_matches?(item, present_only)
  end

  defp kind_matches?(_item, :all), do: true
  defp kind_matches?(%SearchItem{container_type: :movie}, :movies), do: true
  defp kind_matches?(%SearchItem{container_type: :tv_series}, :tv_series), do: true
  defp kind_matches?(%SearchItem{container_type: :movie_series}, :movie_series), do: true
  defp kind_matches?(%SearchItem{container_type: :video_object}, :video_objects), do: true
  defp kind_matches?(_item, _filter), do: false

  defp presence_matches?(_item, false), do: true
  defp presence_matches?(%SearchItem{present?: true}, true), do: true
  defp presence_matches?(_item, true), do: false

  # --- Helpers ---

  defp normalise(value) when is_binary(value), do: value |> String.downcase() |> String.trim()
  defp normalise(_), do: ""

  defp year_from(%Date{year: year}), do: year
  defp year_from(_), do: nil

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])

      _ref ->
        :ok
    end
  end
end
