defmodule MediaCentaur.Library.Views.RankedProjection do
  @moduledoc """
  Shared skeleton for the rank-keyed, ETS-backed Library view projections
  (ADR-041): `ContinueWatching`, `RecentlyAdded`, `HeroCandidates`, `Browse`.

  Each mirrors a `Library.list_*` / `Browser.*` query into a named
  `:ordered_set` ETS table keyed by 0-based display rank, and reads bypass the
  owning `Cache.Worker` GenServer via `:ets.tab2list/1`. The storage, refresh,
  and read *mechanics* are identical across all four; only the source query,
  the view-model mapper, the subscribed topics, and the relevance filter differ
  per projection. This module owns those mechanics as plain functions the
  projections delegate to, so the duplicated `ensure_table` / replace / read /
  read-from-ETS boilerplate lives in exactly one place.

  A `use`-macro was considered (it would also fold the per-projection
  `subscribe` / `relevant?` / `to_view_model`). Plain functions keep those
  genuinely-different pieces explicit and avoid metaprogramming over four
  shipped projections — elixir-thinking's "simplest abstraction wins."
  """
  alias MediaCentaur.Topics

  @ets_opts [:ordered_set, :public, :named_table, read_concurrency: true]

  @doc "Create the projection's `:ordered_set` ETS table if it doesn't exist yet."
  @spec ensure_table(atom()) :: :ok
  def ensure_table(table) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @ets_opts)
      _ref -> :ok
    end

    :ok
  end

  @doc """
  Atomically replace every row with `items`, keyed by 0-based display rank,
  then broadcast `{:library_view_updated, view_tag}` on `library:views`.
  Concurrent readers see either the previous snapshot or the new one, never a
  partial state (single `delete_all_objects` + `insert` pair).

  `:rank_field` (an atom) stamps the assigned rank into that field of each
  item before storing — for view-models that carry their own `:rank`.
  """
  @spec replace_rows(atom(), atom(), [term()], keyword()) :: :ok
  def replace_rows(table, view_tag, items, opts \\ []) do
    ensure_table(table)
    rank_field = Keyword.get(opts, :rank_field)

    rows =
      Enum.with_index(items, fn item, rank ->
        item = if rank_field, do: Map.replace(item, rank_field, rank), else: item
        {rank, item}
      end)

    :ets.delete_all_objects(table)
    :ets.insert(table, rows)

    Topics.publish(
      Topics.library_views(),
      {:library_view_updated, view_tag}
    )

    :ok
  end

  @doc """
  Read the projection from ETS, falling back to `read_from_db` when the table
  is absent — covers test mode (no `Cache.Worker`) and the boot→first-refresh
  window. `limit` of `nil` returns every row.
  """
  @spec read(atom(), non_neg_integer() | nil, (-> [term()])) :: [term()]
  def read(table, limit, read_from_db) when is_function(read_from_db, 0) do
    case :ets.whereis(table) do
      :undefined -> read_from_db.()
      _ref -> read_from_ets(table, limit)
    end
  end

  @doc """
  Read rows from the table in rank order, optionally capped at `limit`.
  `:ordered_set` iterates in key order, so `:ets.tab2list/1` is already
  rank-sorted — no explicit sort needed.
  """
  @spec read_from_ets(atom(), non_neg_integer() | nil) :: [term()]
  def read_from_ets(table, limit) do
    items = table |> :ets.tab2list() |> Enum.map(fn {_rank, item} -> item end)
    if limit, do: Enum.take(items, limit), else: items
  end
end
