defmodule MediaCentaur.Acquisition.Reactor.Handlers do
  @moduledoc """
  Translates release-tracking PubSub events into pursuit-orchestration
  side effects.

  Called by `Acquisition.Reactor` (the GenServer that owns the
  subscription). Splitting the handlers out of the Reactor keeps the
  GenServer module trivial — it's just a subscribe-and-dispatch shim —
  while keeping the drop-planner tick + mode-gate branching here in a
  testable plain-function module.

  ## Public surface

  - `tracking_sweep_completed/0` — run the drop planner tick (ADR-056).
  - `plan_changed/1` — the approval gate for every plan.

  Pure dispatch + Acquisition-context side effects. No GenServer state.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Discovery
  alias MediaCentaur.Acquisition.{DropPlanner, ModeReconciler, PlanEvents, Plans}
  alias MediaCentaur.Acquisition.Plans.Plan
  alias MediaCentaur.ReleaseTracking

  @doc """
  Runs the sweep-tick pipeline — called when the refresher's sweep
  completes a want-ledger sync pass. Mode-off reconciliation (Q11)
  goes first so a flipped-off item's parked drafts and seeking
  pursuits are withdrawn before any new planning.
  """
  @spec tracking_sweep_completed() :: :ok
  def tracking_sweep_completed do
    ModeReconciler.run_pass()
    DropPlanner.run_tick()
  end

  @doc """
  The approval gate (spec 2026-09-05; ADR-056 Q3 for the tracking
  rules): when any plan finishes solving, decide its fate from the
  stamped `approval_policy` —

  * tracking plan, zero found units and nothing offered → delete the
    draft (the wants remain the durable intent; an automated tick that
    found nothing has no record value)
  * tracking plan, zero found units but a pack offered → leave it
    `ready`, whatever the policy: an offer needs a person, and the
    draft on the board is where they see it (spec 2026-09-17 decision 7)
  * tracking plan whose item's mode is now `off` (or whose item is
    gone) → discard. The one live read left: off is a kill switch, not
    a policy, so a mid-solve flip still wins.
  * `review` → leave it `ready`; the draft card on Downloads is the
    steering surface
  * `automatic`, tracking origin → approve when at least one unit was
    found; the want ledger retries the remainder next tick. An
    approval rejection discards (claims exclude those units next tick).
  * `automatic`, manual origin → approve only a clean plan
    (`Plans.clean?/1`); anything else stays `ready` for a person,
    because nothing retries a manual plan's remainder. An approval
    rejection (overlap, nothing to grab) also stays `ready`, logged.

  Non-ready transitions are ignored.
  """
  @spec plan_changed(PlanEvents.Changed.t()) :: :ok
  def plan_changed(%PlanEvents.Changed{status: "ready", plan_id: plan_id}) do
    case Plans.fetch(plan_id) do
      {:ok, %Plan{status: "ready"} = plan} -> gate(plan)
      _other -> :ok
    end
  end

  def plan_changed(%PlanEvents.Changed{}), do: :ok

  defp gate(%Plan{origin: "tracking"} = plan) do
    units = Plans.units_for(plan.id)
    found = Enum.count(units, &(&1.status == "found"))
    offered? = Enum.any?(units, &(&1.status == "unfound" and is_binary(&1.offered_guid)))

    cond do
      found == 0 and not offered? -> Plans.delete_tracking_draft(plan)
      tracking_item_off?(plan) -> discard(plan)
      # An offer is never automatic: the draft waits on the board for a
      # person, and the one-active-draft rule keeps the want from being
      # re-planned underneath it (spec 2026-09-17 decision 7).
      found == 0 -> :ok
      plan.approval_policy == "review" -> :ok
      true -> approve_or_discard(plan)
    end

    :ok
  end

  defp gate(%Plan{approval_policy: "automatic"} = plan) do
    if Plans.clean?(plan), do: approve_or_park(plan)
    :ok
  end

  defp gate(%Plan{}), do: :ok

  defp tracking_item_off?(plan) do
    case plan.tracking_item_id && ReleaseTracking.get_item(plan.tracking_item_id) do
      nil ->
        true

      item ->
        not Discovery.grabs?(item.tmdb_id, item.media_type)
    end
  end

  defp approve_or_discard(plan) do
    case Plans.approve(plan) do
      {:ok, committed} ->
        Log.info(:acquisition, "tracking plan auto-committed — #{committed.title}")

      {:error, reason} ->
        Log.warning(
          :acquisition,
          "tracking plan auto-approve rejected — #{plan.title} — #{inspect(reason)}"
        )

        discard(plan)
    end
  end

  defp approve_or_park(plan) do
    case Plans.approve(plan) do
      {:ok, committed} ->
        Log.info(:acquisition, "plan auto-committed — #{committed.title}")

      {:error, reason} ->
        Log.warning(
          :acquisition,
          "plan auto-approve rejected, parked for review — #{plan.title} — #{inspect(reason)}"
        )
    end
  end

  defp discard(plan) do
    case Plans.discard(plan) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end
end
