defmodule MediaCentaur.Acquisition.Pursuits.Observations do
  @moduledoc """
  Observation-state accounting and signal-derived event emission.

  Two responsibilities, at two deliberately different levels:

  1. **Per-unit signal reconciliation** (`refresh!/4,5`) — keeps the
     unit's `stall_first_seen_at` / `zero_seeders_first_seen_at`
     timestamps current so `Policy` can stay pure (ADR-055 — the unit
     carries the attempt thread). `Policy` reads them as opaque inputs;
     the deciding-whether-the-signal-is-present logic lives here.

  2. **Pursuit-level lifecycle events** (`observe_pursuit!/3,4`) — emits
     `DownloadStarted` / `HealthChanged` to the timeline when the
     pursuit's tracked torrent transitions. The torrent is found by the
     pursuit's latest release title, so it is a *pursuit-level* fact:
     every unit of a composite pursuit shares it. Observing it per-unit
     (the original design) multiplied each transition into one timeline
     row per unit — a 38-episode season pack minted 38 identical
     "Download started" rows. The Watcher calls this once per pursuit
     per tick, before the per-unit pass.

  These are *signal-derived* events — facts about what the download
  client did, not decisions about what the pursuit should do. ADR-039
  reserves `Policy` for decision events (`auto_cancel`,
  `request_decision`, `exhaust`); signal events belong in the pre-Policy
  phase because their existence is a property of the observed
  transition, not a choice.

  Signal mapping (per-unit):

    * `health in [:soft_stall, :frozen]` → stall observation
    * `state == :stalled`                → zero-seeders observation
      (qBittorrent's `stalledDL` means "no peers / no progress" — the
      strongest "definitely dead release" signal we have without an
      explicit seeder count column on `QueueItem`)

  Recovery clears the corresponding timestamp so the window starts
  fresh. When the queue is `:unknown` (download client unreachable)
  nothing is touched — we don't penalise the user for an infrastructure
  outage. When the tracked torrent is missing from the queue this tick,
  the pursuit's `last_queue_state`/`last_queue_health` are preserved (a
  transient absence shouldn't synthesize a transition). A present item
  whose health is `nil` stores a real NULL — never the string `"nil"` —
  so the observation converges instead of re-emitting every tick.
  """

  import Ecto.Query

  alias MediaCentaur.Acquisition.Pursuits.Events
  alias MediaCentaur.Acquisition.Pursuits.Events.{DownloadStarted, HealthChanged}
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Unit}
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Downloads.QueueItem
  alias MediaCentaur.Repo

  @doc """
  Refreshes a unit's stall / zero-seeder observation timestamps
  in-place. Returns the refreshed unit. Idempotent. Emits no events —
  lifecycle events are `observe_pursuit!/4`'s job.

  The 3-arity issues one extra DB query per call to find the latest
  release title for the unit's pursuit; callers that already have that
  value in hand (e.g. `Pursuits.Watcher` after batch-fetching) should
  use `refresh!/5` to skip the query.
  """
  @spec refresh!(Pursuit.t(), Unit.t(), [QueueItem.t()] | :unknown, DateTime.t()) :: Unit.t()
  def refresh!(%Pursuit{} = pursuit, %Unit{} = unit, queue_items_or_unknown, now) do
    release_title = latest_release_title(pursuit.id)
    refresh!(pursuit, unit, queue_items_or_unknown, now, release_title)
  end

  @doc """
  Pre-fetched variant of `refresh!/4`. `release_title` is the pursuit's
  latest non-nil `Target.release_title` (or `nil` if none). Used by the
  Watcher's batched pass so per-tick DB cost is constant rather than
  scaling with the active-unit count.
  """
  @spec refresh!(Pursuit.t(), Unit.t(), [QueueItem.t()] | :unknown, DateTime.t(), String.t() | nil) ::
          Unit.t()
  def refresh!(%Pursuit{}, %Unit{} = unit, :unknown, _now, _release_title), do: unit

  def refresh!(%Pursuit{}, %Unit{} = unit, queue_items, %DateTime{} = now, release_title)
      when is_list(queue_items) do
    queue_item = find_queue_item(queue_items, release_title)

    unit
    |> Ecto.Changeset.change(
      stall_first_seen_at: next_timestamp(unit.stall_first_seen_at, stalling?(queue_item), now),
      zero_seeders_first_seen_at:
        next_timestamp(unit.zero_seeders_first_seen_at, no_seeders?(queue_item), now)
    )
    |> Repo.update!()
  end

  @doc """
  Observes the pursuit's tracked torrent once per tick: persists the
  latest `(state, health)` on the pursuit and emits `DownloadStarted`
  (first non-nil observation) or `HealthChanged` (subsequent
  transition) to the timeline. No event for "no change" ticks — the
  timeline records story beats, not heartbeats. Returns the refreshed
  pursuit.

  The 3-arity looks up the pursuit's latest release title; the Watcher
  passes it pre-fetched via the 4-arity.
  """
  @spec observe_pursuit!(Pursuit.t(), [QueueItem.t()] | :unknown, DateTime.t()) :: Pursuit.t()
  def observe_pursuit!(%Pursuit{} = pursuit, queue_items_or_unknown, now) do
    release_title = latest_release_title(pursuit.id)
    observe_pursuit!(pursuit, queue_items_or_unknown, now, release_title)
  end

  @spec observe_pursuit!(
          Pursuit.t(),
          [QueueItem.t()] | :unknown,
          DateTime.t(),
          String.t() | nil
        ) :: Pursuit.t()
  def observe_pursuit!(%Pursuit{} = pursuit, :unknown, _now, _release_title), do: pursuit

  def observe_pursuit!(%Pursuit{} = pursuit, queue_items, %DateTime{} = now, release_title)
      when is_list(queue_items) do
    case find_queue_item(queue_items, release_title) do
      # Absent this tick — preserve the last observation; a transient
      # absence shouldn't synthesize a transition.
      nil ->
        pursuit

      %QueueItem{} = queue_item ->
        to_state = observed_state(queue_item)
        to_health = observed_health(queue_item)

        pursuit
        |> derive_transition_event(queue_item, now)
        |> emit()

        pursuit
        |> Ecto.Changeset.change(last_queue_state: to_state, last_queue_health: to_health)
        |> Repo.update!()
    end
  end

  defp find_queue_item(_queue_items, nil), do: nil

  defp find_queue_item(queue_items, title) when is_binary(title) do
    Enum.find(queue_items, &(&1.title == title))
  end

  defp latest_release_title(pursuit_id) do
    Target
    |> where([t], t.pursuit_id == ^pursuit_id and not is_nil(t.release_title))
    |> order_by([t], desc: t.inserted_at)
    |> limit(1)
    |> select([t], t.release_title)
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

  # Stringify only real values — `Atom.to_string(nil)` is the string
  # "nil", which once leaked into payloads and UI copy as the literal
  # word.
  defp observed_state(%QueueItem{state: state}) when is_atom(state) and not is_nil(state),
    do: Atom.to_string(state)

  defp observed_state(%QueueItem{}), do: nil

  defp observed_health(%QueueItem{health: health}) when is_atom(health) and not is_nil(health),
    do: Atom.to_string(health)

  defp observed_health(%QueueItem{}), do: nil

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
