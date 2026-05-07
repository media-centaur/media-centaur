defmodule MediaCentarr.Acquisition.Pursuits.Observations do
  @moduledoc """
  Observation-state accounting for pursuits.

  `refresh!/3` walks one pursuit's latest grab against the current queue
  snapshot and updates the persistent `stall_first_seen_at` /
  `zero_seeders_first_seen_at` timestamps. The Watcher calls this once
  per pursuit per tick before building a `Snapshot`; the resulting
  timestamps are how `Snapshot` decides whether the corresponding
  threshold window has elapsed.

  Signal mapping:

    * `health in [:soft_stall, :frozen]` → stall observation
    * `state == :stalled`                → zero-seeders observation
      (qBittorrent's `stalledDL` means "no peers / no progress" — the
      strongest "definitely dead release" signal we have without an
      explicit seeder count column on `QueueItem`)

  When a queue item recovers (no longer matching either signal), the
  corresponding timestamp is cleared so the window starts fresh next
  time. When the queue is `:unknown` (download client unreachable) the
  pursuit is left as-is — we don't penalise the user for an
  infrastructure outage.
  """

  import Ecto.Query

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits.Pursuit
  alias MediaCentarr.Acquisition.QueueItem
  alias MediaCentarr.Repo

  @doc """
  Refreshes a pursuit's observation timestamps in-place. Returns the
  refreshed pursuit. Idempotent — calling repeatedly with the same
  inputs yields the same persisted state.
  """
  @spec refresh!(Pursuit.t(), [QueueItem.t()] | :unknown, DateTime.t()) :: Pursuit.t()
  def refresh!(%Pursuit{} = pursuit, :unknown, _now), do: pursuit

  def refresh!(%Pursuit{} = pursuit, queue_items, %DateTime{} = now) when is_list(queue_items) do
    queue_item = find_queue_item(pursuit, queue_items)

    pursuit
    |> Ecto.Changeset.change(
      stall_first_seen_at: next_timestamp(pursuit.stall_first_seen_at, stalling?(queue_item), now),
      zero_seeders_first_seen_at:
        next_timestamp(pursuit.zero_seeders_first_seen_at, no_seeders?(queue_item), now)
    )
    |> Repo.update!()
  end

  defp find_queue_item(%Pursuit{id: pursuit_id}, queue_items) do
    case latest_release_title(pursuit_id) do
      nil -> nil
      title -> Enum.find(queue_items, &(&1.title == title))
    end
  end

  defp latest_release_title(pursuit_id) do
    Grab
    |> where([g], g.pursuit_id == ^pursuit_id and not is_nil(g.release_title))
    |> order_by([g], desc: g.inserted_at)
    |> limit(1)
    |> select([g], g.release_title)
    |> Repo.one()
  end

  defp stalling?(nil), do: false
  defp stalling?(%QueueItem{state: :stalled}), do: true
  defp stalling?(%QueueItem{health: health}) when health in [:soft_stall, :frozen], do: true
  defp stalling?(%QueueItem{}), do: false

  defp no_seeders?(nil), do: false
  defp no_seeders?(%QueueItem{state: :stalled}), do: true
  defp no_seeders?(%QueueItem{}), do: false

  # Set timestamp on first observation, preserve once set, clear once recovered.
  defp next_timestamp(existing, true, now), do: existing || now
  defp next_timestamp(_existing, false, _now), do: nil
end
