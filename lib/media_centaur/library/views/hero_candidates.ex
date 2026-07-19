defmodule MediaCentaur.Library.Views.HeroCandidates do
  @moduledoc """
  ETS-backed projection of Hero Candidate rows (ADR-041).

  Mirrors the output of `MediaCentaur.Library.list_hero_candidates/1`
  into a named ETS table holding `HeroCandidatesItem` structs keyed
  by display rank. Reads bypass the GenServer entirely — see
  `MediaCentaur.Library.Views.hero_candidates/1`.

  ## Refresh triggers

  Subscribes to two source topics:

    * `library:updates` — entity creates/edits/deletes (coalesced
      upstream by `Library.BroadcastCoalescer`). New backdrops,
      description edits, and deletes all flow through here.
    * `library:availability` — drive-mount and drive-unmount events.
      The underlying query reads `library_watched_files` rows, whose
      Phase-3 FK to `library_file_presences` (cascade-delete) makes
      WatchedFile existence equivalent to "current presence on disk."

  ## Storage

    * `:library_view_hero_candidates` — `:ordered_set`, `:public`,
      `:read_concurrency, true`. Keyed by display rank (`0..n-1`).
    * Refreshes replace every row in a single `:ets.delete_all_objects`
      + `:ets.insert` pair. Concurrent readers see either the previous
      snapshot or the new one, never a partial state.
  """
  @behaviour MediaCentaur.Cache

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Availability
  alias MediaCentaur.Library.Views.HeroCandidatesItem
  alias MediaCentaur.Library.Views.RankedProjection
  alias MediaCentaur.Topics

  @table :library_view_hero_candidates

  @impl MediaCentaur.Cache
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.library_updates())
    Availability.subscribe()
    :ok
  end

  @impl MediaCentaur.Cache
  def relevant?({:entities_changed, _}), do: true
  def relevant?({:availability_changed, _, _}), do: true
  def relevant?(_), do: false

  @impl MediaCentaur.Cache
  def refresh_cache do
    items =
      []
      |> Library.list_hero_candidates()
      |> Enum.map(&to_view_model/1)

    RankedProjection.replace_rows(@table, :hero_candidates, items)
  end

  @doc """
  Read the projection. Falls back to the underlying DB query when the
  ETS table is absent — covers test mode (Cache.Worker not started)
  and the brief window between boot and first refresh.
  """
  @spec read(keyword()) :: [HeroCandidatesItem.t()]
  def read(opts \\ []) do
    limit = Keyword.get(opts, :limit)
    RankedProjection.read(@table, limit, fn -> read_from_db(limit) end)
  end

  defp read_from_db(limit) do
    [limit: limit]
    |> Library.list_hero_candidates()
    |> Enum.map(&to_view_model/1)
  end

  defp to_view_model(row) do
    %HeroCandidatesItem{
      id: row.id,
      name: row.name,
      year: Map.get(row, :year),
      runtime_minutes: Map.get(row, :runtime_minutes),
      genres: Map.get(row, :genres),
      overview: Map.get(row, :overview),
      backdrop_url: Map.get(row, :backdrop_url),
      logo_url: Map.get(row, :logo_url)
    }
  end
end
