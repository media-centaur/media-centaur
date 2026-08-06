defmodule MediaCentaur.Status.Views.Overview do
  @moduledoc """
  ETS-backed projection of the Status page's library overview
  (`MediaCentaur.Status.load_overview/0` — aggregate counts, total size,
  recent additions, pending work, completeness gaps).

  `load_overview/0` runs a per-image disk check and several aggregate
  queries, so it must never run on a LiveView navigation path. This
  projection computes it in a `Cache.Worker` and serves it as a
  single-row ETS lookup.

  ## Refresh triggers

    * `library:updates` — entity creates / edits / deletes (coalesced
      upstream) drive the counts, size, and recent-additions slices.
    * `review:updates` — review intake / resolution drives
      `pending_review_count`.
    * A periodic tick (registered in `application.ex`) as the drift net
      for slices with no dedicated event — in-flight pursuits, missing
      artwork, completeness. This is strictly fresher than the page's
      previous behaviour, where the overview refreshed only on a
      debounced `entities_changed` while someone was on the page.

  ## Storage

  `:status_view_overview` — `:set`, `:public`, `:named_table`,
  `:read_concurrency, true`, single `:snapshot` row. Refreshes replace
  the row atomically; readers see the previous or the new snapshot,
  never a partial state.
  """
  @behaviour MediaCentaur.Cache

  alias MediaCentaur.Review.Events.FileAdded
  alias MediaCentaur.Review.Events.FileReviewed
  alias MediaCentaur.Review.Events.GroupApproved
  alias MediaCentaur.Status
  alias MediaCentaur.Status.LibraryOverview
  alias MediaCentaur.Topics

  @table :status_view_overview

  @impl MediaCentaur.Cache
  def subscribe do
    Topics.subscribe(Topics.library_updates())
    Topics.subscribe(Topics.review_updates())
    :ok
  end

  @impl MediaCentaur.Cache
  def relevant?({:entities_changed, _payload}), do: true
  def relevant?({:file_added, %FileAdded{}}), do: true
  def relevant?({:file_reviewed, %FileReviewed{}}), do: true
  def relevant?({:group_approved, %GroupApproved{}}), do: true
  def relevant?(_message), do: false

  @impl MediaCentaur.Cache
  def refresh_cache do
    ensure_table()

    snapshot = Status.load_overview()
    :ets.insert(@table, {:snapshot, snapshot})

    Topics.publish(
      Topics.status_views(),
      {:status_view_updated, :overview}
    )

    :ok
  end

  @doc """
  Read the cached snapshot. Falls back to the live computation when the
  table is absent (test mode) or not yet primed (boot window).
  """
  @spec read() :: LibraryOverview.t()
  def read do
    case :ets.whereis(@table) do
      :undefined -> Status.load_overview()
      _ref -> read_from_ets()
    end
  end

  defp read_from_ets do
    case :ets.lookup(@table, :snapshot) do
      [{:snapshot, snapshot}] -> snapshot
      [] -> Status.load_overview()
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
      _ref -> :ok
    end
  end
end
