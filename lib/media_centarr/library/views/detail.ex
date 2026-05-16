defmodule MediaCentarr.Library.Views.Detail do
  @moduledoc """
  ETS-backed projection of detail-modal view-models keyed by
  `PlayableItem` UUID (ADR-041, Library Schema v2 Phase 3 Task B).

  One row per `Library.PlayableItem`. Each row carries the container
  metadata, embedded cast/crew, extras, external_ids, and a `:present?`
  flag derived from the leaf's WatchedFile state. Reads bypass the
  GenServer entirely — see `Library.Views.detail/1` and
  `Library.Views.detail_by_container/2`.

  ## Refresh strategy

  Two flavours:

    * **Full rebuild** at boot via `refresh_cache/0` — walks every
      PlayableItem and inserts one row per leaf.
    * **Partial rebuild** via `handle_message/1` — translates the
      incoming event to the set of affected `playable_item_id`s and
      rebuilds only those rows. Per-PlayableItem partial refresh keeps
      detail rebuilds cheap when only one entity changes; a TVSeries
      with 100 episodes does not cause 100 rebuilds for an unrelated
      Movie metadata edit.

  ## Refresh triggers

    * `library:updates` — `EntitiesChanged{entity_ids:}` rebuilds the
      rows for each affected entity's PlayableItems.
    * `library:availability` — drive-mount / drive-unmount: full rebuild
      (presence flips can affect many rows; the cheap path is to
      reconcile the whole table).

  ## Storage

    * `:library_view_detail` — `:set`, `:public`, `:named_table`,
      `:read_concurrency, true`. Keyed by `playable_item_id`.

  ## Broadcast contract

  Emits `{:library_view_updated, :detail, playable_item_id}` on the
  `library:views` topic for each row touched. The 3-tuple shape lets
  DetailLive subscribe to only its current PlayableItem and ignore
  unrelated updates. This is intentionally distinct from Browse's
  2-tuple `{:library_view_updated, :browse}`, which discriminates the
  whole-table refresh.
  """
  @behaviour MediaCentarr.Cache

  import Ecto.Query

  alias MediaCentarr.Library
  alias MediaCentarr.Library.Availability
  alias MediaCentarr.Library.Episode
  alias MediaCentarr.Library.Movie
  alias MediaCentarr.Library.PlayableItem
  alias MediaCentarr.Library.Season
  alias MediaCentarr.Library.TVSeries
  alias MediaCentarr.Library.VideoObject
  alias MediaCentarr.Library.Views.DetailItem
  alias MediaCentarr.Library.WatchedFile
  alias MediaCentarr.Repo
  alias MediaCentarr.Topics
  alias MediaCentarr.Watcher.KnownFile

  @table :library_view_detail

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

    items = build_all_items()

    :ets.delete_all_objects(@table)

    Enum.each(items, fn item ->
      :ets.insert(@table, {item.playable_item_id, item})
      broadcast_row(item.playable_item_id)
    end)

    :ok
  end

  @impl MediaCentarr.Cache
  def handle_message({:entities_changed, %{entity_ids: ids}}) when is_list(ids) do
    ensure_table()

    case Library.playable_item_ids_for_entities(ids) do
      [] ->
        # The entity may have been deleted — its PlayableItems are gone.
        # Sweep any stale rows from the table that point at these
        # container_ids. We can't ask the DB; rely on the ETS index.
        Enum.each(ids, &delete_rows_for_container_id/1)
        :ok

      playable_item_ids ->
        Enum.each(playable_item_ids, &rebuild_row/1)
        # Also sweep rows whose PlayableItems no longer exist for the
        # given container ids (e.g. partial deletion).
        Enum.each(ids, fn container_id ->
          Enum.each(stale_rows_for_container_id(container_id, playable_item_ids), &delete_row/1)
        end)

        :ok
    end
  end

  def handle_message({:availability_changed, _dir, _state}) do
    # Presence flips can affect many rows; the cheap path is a full
    # rebuild rather than walking every row to recompute `:present?`.
    refresh_cache()
  end

  def handle_message(_msg), do: :ok

  @doc """
  Read the projection for a single `playable_item_id`. Returns the
  cached `DetailItem` or nil when no row exists.

  Falls back to a live build when the ETS table is absent — covers
  test mode (Cache.Worker not started) and the brief window between
  boot and first refresh.
  """
  @spec read(Ecto.UUID.t()) :: DetailItem.t() | nil
  def read(playable_item_id) when is_binary(playable_item_id) do
    case :ets.whereis(@table) do
      :undefined -> build_item_for_playable_item_id(playable_item_id)
      _ref -> read_from_ets(playable_item_id)
    end
  end

  def read(_), do: nil

  @doc """
  Read the projection by container UUID for single-leaf containers
  (`:movie` and `:video_object`). For multi-cut containers, returns the
  canonical `position == 1` PlayableItem's row.

  Returns nil for container_types with no canonical leaf:

    * `:tv_series` — N episodes per series, no canonical playable leaf
      at the container level.
    * `:movie_series` — same rationale; consumers want a child Movie.
    * `:episode` — semantics deferred; callers should hold the
      `playable_item_id` rather than the episode UUID.
  """
  @spec read_by_container(atom(), Ecto.UUID.t()) :: DetailItem.t() | nil
  def read_by_container(container_type, container_id)
      when container_type in [:movie, :video_object] and is_binary(container_id) do
    case :ets.whereis(@table) do
      :undefined ->
        build_item_for_container(container_type, container_id)

      _ref ->
        read_from_ets_by_container(container_type, container_id)
    end
  end

  def read_by_container(_type, _id), do: nil

  # --- ETS read paths ---

  defp read_from_ets(playable_item_id) do
    case :ets.lookup(@table, playable_item_id) do
      [{^playable_item_id, %DetailItem{} = item}] -> item
      _ -> nil
    end
  end

  defp read_from_ets_by_container(container_type, container_id) do
    # Match-spec: rows where (container_type, container_id) matches and
    # position == 1. Returns DetailItems sorted by position; pick the
    # first.
    match_spec = [
      {{:_, %{container_type: container_type, container_id: container_id, position: 1}}, [], [:"$_"]}
    ]

    case :ets.select(@table, match_spec) do
      [{_pi_id, %DetailItem{} = item}] -> item
      [{_pi_id, %DetailItem{} = item} | _] -> item
      _ -> nil
    end
  end

  # --- Build paths ---

  defp build_all_items do
    PlayableItem
    |> Repo.all()
    |> Enum.map(&build_item_for_playable_item/1)
    |> Enum.reject(&is_nil/1)
  end

  defp build_item_for_playable_item_id(playable_item_id) do
    case Repo.get(PlayableItem, playable_item_id) do
      nil -> nil
      %PlayableItem{} = item -> build_item_for_playable_item(item)
    end
  end

  defp build_item_for_container(:movie, container_id) do
    case Repo.one(
           from(p in PlayableItem,
             where: p.container_type == :movie and p.container_id == ^container_id,
             order_by: [asc: p.position],
             limit: 1
           )
         ) do
      nil -> nil
      %PlayableItem{} = item -> build_item_for_playable_item(item)
    end
  end

  defp build_item_for_container(:video_object, container_id) do
    case Repo.one(
           from(p in PlayableItem,
             where: p.container_type == :video_object and p.container_id == ^container_id,
             order_by: [asc: p.position],
             limit: 1
           )
         ) do
      nil -> nil
      %PlayableItem{} = item -> build_item_for_playable_item(item)
    end
  end

  defp build_item_for_playable_item(%PlayableItem{container_type: type, container_id: cid} = item) do
    case fetch_container(type, cid) do
      nil ->
        nil

      container ->
        %DetailItem{
          playable_item_id: item.id,
          container_type: type,
          container_id: cid,
          name: leaf_name(type, item, container),
          position: item.position,
          duration_seconds: item.duration_seconds,
          date_published: leaf_date_published(type, container),
          description: leaf_description(type, container),
          parent_container_type: parent_container_type(type),
          parent_container_id: parent_container_id(type, container),
          parent_container_name: parent_container_name(type, container),
          container_name: container_name(type, container),
          container_description: container_description(type, container),
          container_year: container_year(type, container),
          container_url: container_url(type, container),
          container_tagline: container_tagline(type, container),
          container_genres: container_genres(type, container),
          container_studio: container_studio(type, container),
          container_country_code: container_country_code(type, container),
          container_original_language: container_original_language(type, container),
          container_network: container_network(type, container),
          container_status: container_status(type, container),
          container_duration_seconds: container_duration_seconds(type, container),
          container_content_rating: container_content_rating(type, container),
          container_aggregate_rating: container_aggregate_rating(type, container),
          container_vote_count: container_vote_count(type, container),
          container_number_of_seasons: container_number_of_seasons(type, container),
          cast: container_cast(type, container),
          crew: container_crew(type, container),
          extras: container_extras(type, container),
          external_ids: container_external_ids(type, container),
          imdb_id: external_id_value(container_external_ids(type, container), "imdb"),
          tmdb_id: external_id_value(container_external_ids(type, container), "tmdb"),
          present?: any_present_file?(item.id)
        }
    end
  end

  defp rebuild_row(playable_item_id) do
    case build_item_for_playable_item_id(playable_item_id) do
      nil ->
        delete_row(playable_item_id)

      %DetailItem{} = item ->
        :ets.insert(@table, {playable_item_id, item})
        broadcast_row(playable_item_id)
    end
  end

  defp delete_row(playable_item_id) do
    :ets.delete(@table, playable_item_id)
    broadcast_row(playable_item_id)
  end

  defp delete_rows_for_container_id(container_id) do
    @table
    |> :ets.select([
      {{:"$1", %{container_id: container_id}}, [], [:"$1"]}
    ])
    |> Enum.each(&delete_row/1)
  end

  defp stale_rows_for_container_id(container_id, live_ids) do
    @table
    |> :ets.select([
      {{:"$1", %{container_id: container_id}}, [], [:"$1"]}
    ])
    |> Enum.reject(&(&1 in live_ids))
  end

  defp broadcast_row(playable_item_id) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.library_views(),
      {:library_view_updated, :detail, playable_item_id}
    )
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])

      _ref ->
        :ok
    end
  end

  # --- Container fetchers with preloads ---

  defp fetch_container(:movie, id) do
    Repo.one(
      from(m in Movie,
        where: m.id == ^id,
        preload: [:extras, :external_ids]
      )
    )
  end

  defp fetch_container(:episode, id) do
    Repo.one(
      from(e in Episode,
        where: e.id == ^id,
        preload: [season: [tv_series: [:extras, :external_ids]]]
      )
    )
  end

  defp fetch_container(:video_object, id) do
    Repo.one(
      from(v in VideoObject,
        where: v.id == ^id,
        preload: [:external_ids]
      )
    )
  end

  defp fetch_container(_, _), do: nil

  # --- Leaf-level fields ---

  defp leaf_name(:episode, _item, %Episode{name: name}) when is_binary(name) and name != "", do: name
  defp leaf_name(:movie, _item, %Movie{name: name}), do: name
  defp leaf_name(:video_object, _item, %VideoObject{name: name}), do: name
  defp leaf_name(_, %PlayableItem{name: name}, _) when is_binary(name), do: name
  defp leaf_name(_, _item, container), do: Map.get(container, :name)

  defp leaf_date_published(:episode, _), do: nil
  defp leaf_date_published(_, %{date_published: date}), do: date
  defp leaf_date_published(_, _), do: nil

  defp leaf_description(_, %{description: desc}), do: desc
  defp leaf_description(_, _), do: nil

  # --- Parent container resolution (Episode → TVSeries) ---

  defp parent_container_type(:episode), do: :tv_series
  defp parent_container_type(_), do: nil

  defp parent_container_id(:episode, %Episode{season: %Season{tv_series: %TVSeries{id: id}}}), do: id
  defp parent_container_id(_, _), do: nil

  defp parent_container_name(:episode, %Episode{season: %Season{tv_series: %TVSeries{name: name}}}),
    do: name

  defp parent_container_name(_, _), do: nil

  # --- Top-level container metadata. For Episodes the top-level
  # container is the TVSeries (parent), so these reach through.

  defp top_level_container(:episode, %Episode{season: %Season{tv_series: %TVSeries{} = series}}),
    do: series

  defp top_level_container(_, container), do: container

  defp container_name(type, container), do: Map.get(top_level_container(type, container), :name)

  defp container_description(type, container),
    do: Map.get(top_level_container(type, container), :description)

  defp container_year(type, container) do
    case top_level_container(type, container) do
      %{date_published: %Date{year: year}} -> year
      _ -> nil
    end
  end

  defp container_url(type, container), do: Map.get(top_level_container(type, container), :url)

  defp container_tagline(type, container), do: Map.get(top_level_container(type, container), :tagline)

  defp container_genres(type, container), do: Map.get(top_level_container(type, container), :genres)

  defp container_studio(type, container), do: Map.get(top_level_container(type, container), :studio)

  defp container_country_code(type, container),
    do: Map.get(top_level_container(type, container), :country_code)

  defp container_original_language(type, container),
    do: Map.get(top_level_container(type, container), :original_language)

  defp container_network(type, container), do: Map.get(top_level_container(type, container), :network)

  defp container_status(type, container), do: Map.get(top_level_container(type, container), :status)

  defp container_duration_seconds(type, container),
    do: Map.get(top_level_container(type, container), :duration_seconds)

  defp container_content_rating(type, container),
    do: Map.get(top_level_container(type, container), :content_rating)

  defp container_aggregate_rating(type, container),
    do: Map.get(top_level_container(type, container), :aggregate_rating_value)

  defp container_vote_count(type, container),
    do: Map.get(top_level_container(type, container), :vote_count)

  defp container_number_of_seasons(type, container),
    do: Map.get(top_level_container(type, container), :number_of_seasons)

  defp container_cast(type, container), do: Map.get(top_level_container(type, container), :cast)

  defp container_crew(type, container), do: Map.get(top_level_container(type, container), :crew)

  defp container_extras(type, container), do: Map.get(top_level_container(type, container), :extras)

  defp container_external_ids(type, container),
    do: Map.get(top_level_container(type, container), :external_ids)

  defp external_id_value(nil, _), do: nil

  defp external_id_value(external_ids, source) when is_list(external_ids) do
    Enum.find_value(external_ids, fn
      %{source: ^source, external_id: value} -> value
      _ -> nil
    end)
  end

  defp external_id_value(_, _), do: nil

  # --- Presence ---

  defp any_present_file?(playable_item_id) do
    query =
      from(w in WatchedFile,
        join: k in KnownFile,
        on: k.file_path == w.file_path,
        where: w.playable_item_id == ^playable_item_id and k.state == :present,
        select: 1,
        limit: 1
      )

    Repo.one(query) == 1
  end
end
