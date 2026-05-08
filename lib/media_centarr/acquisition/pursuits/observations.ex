defmodule MediaCentarr.Acquisition.Pursuits.Observations do
  @moduledoc """
  Observation-state accounting for pursuits.

  `refresh!/3` reconciles a pursuit's persisted observation state against
  one snapshot of the download-client queue. The Watcher calls this once
  per pursuit per tick before building a `Snapshot`. Three things are
  reconciled:

    * `stall_first_seen_at` / `zero_seeders_first_seen_at` — set on the
      first observation of the corresponding signal, preserved while
      observed, cleared once recovered. Drive Policy's stall and
      zero-seeders rules.
    * `last_queue_state` / `last_queue_health` — the last observed
      `(state, health)` tuple for the pursuit's tracked queue item.
      Used to detect lifecycle transitions across ticks.
    * Lifecycle events on the timeline — when the observed
      `(state, health)` differs from `(last_queue_state, last_queue_health)`,
      emit `DownloadStarted` (first non-nil observation) or
      `HealthChanged` (subsequent transition). No event for "no change"
      ticks — the timeline records story beats, not heartbeats.

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
  infrastructure outage. When the pursuit's tracked torrent is missing
  from the queue this tick, `last_queue_state`/`last_queue_health` are
  preserved (a transient absence shouldn't synthesize a transition).
  """

  import Ecto.Query

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Events.{DownloadStarted, HealthChanged}
  alias MediaCentarr.Acquisition.QueueItem
  alias MediaCentarr.Repo

  @doc """
  Refreshes a pursuit's observation state in-place. Returns the
  refreshed pursuit. Idempotent — calling repeatedly with the same
  inputs yields the same persisted state and emits no duplicate events.
  """
  @spec refresh!(Pursuit.t(), [QueueItem.t()] | :unknown, DateTime.t()) :: Pursuit.t()
  def refresh!(%Pursuit{} = pursuit, :unknown, _now), do: pursuit

  def refresh!(%Pursuit{} = pursuit, queue_items, %DateTime{} = now) when is_list(queue_items) do
    queue_item = find_queue_item(pursuit, queue_items)

    refreshed =
      pursuit
      |> Ecto.Changeset.change(
        stall_first_seen_at: next_timestamp(pursuit.stall_first_seen_at, stalling?(queue_item), now),
        zero_seeders_first_seen_at:
          next_timestamp(pursuit.zero_seeders_first_seen_at, no_seeders?(queue_item), now),
        last_queue_state: next_observed(pursuit.last_queue_state, observed_state(queue_item)),
        last_queue_health: next_observed(pursuit.last_queue_health, observed_health(queue_item))
      )
      |> Repo.update!()

    pursuit
    |> derive_transition_event(queue_item, now)
    |> emit()

    refreshed
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

  defp observed_state(nil), do: nil
  defp observed_state(%QueueItem{state: state}) when is_atom(state), do: Atom.to_string(state)
  defp observed_state(%QueueItem{}), do: nil

  defp observed_health(nil), do: nil
  defp observed_health(%QueueItem{health: health}) when is_atom(health), do: Atom.to_string(health)
  defp observed_health(%QueueItem{}), do: nil

  # Preserve the last directly-observed value when this tick has no observation;
  # otherwise overwrite with what we just saw.
  defp next_observed(existing, nil), do: existing
  defp next_observed(_existing, observed), do: observed

  defp derive_transition_event(%Pursuit{}, nil, _now), do: nil

  defp derive_transition_event(%Pursuit{} = pursuit, %QueueItem{} = queue_item, now) do
    to_state = observed_state(queue_item)
    to_health = observed_health(queue_item)
    from_state = pursuit.last_queue_state
    from_health = pursuit.last_queue_health

    cond do
      is_nil(from_state) and is_nil(from_health) and not (is_nil(to_state) and is_nil(to_health)) ->
        %DownloadStarted{
          pursuit_id: pursuit.id,
          pursuit_title: pursuit.title,
          occurred_at: now,
          client: "qbittorrent",
          infohash: nil
        }

      from_state != to_state or from_health != to_health ->
        %HealthChanged{
          pursuit_id: pursuit.id,
          pursuit_title: pursuit.title,
          occurred_at: now,
          from_state: from_state,
          to_state: to_state,
          from_health: from_health,
          to_health: to_health
        }

      true ->
        nil
    end
  end

  defp emit(nil), do: :ok
  defp emit(event), do: Events.record(event)
end
