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
  - `plan_changed/1` — the mode gate for tracking-born plans.

  Pure dispatch + Acquisition-context side effects. No GenServer state.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.{AutoGrabSettings, DropPlanner, ModeReconciler, PlanEvents, Plans}
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
  The mode gate for tracking-born plans (ADR-056 Q3): when a tracking
  plan finishes solving, decide its fate from the item's effective
  auto-grab mode —

  * zero found units → delete the draft (the wants remain the durable
    intent; an automated tick that found nothing has no record value)
  * `ask` → leave it `ready`; the draft card on Downloads is the
    steering surface
  * `off` (flipped mid-flight) → discard
  * otherwise (auto) → approve; an overlap or nothing-to-grab rejection
    discards (claims will exclude those units next tick)

  Non-tracking plans and non-ready transitions are ignored.
  """
  @spec plan_changed(PlanEvents.Changed.t()) :: :ok
  def plan_changed(%PlanEvents.Changed{status: "ready", plan_id: plan_id}) do
    case Plans.fetch(plan_id) do
      {:ok, %Plan{origin: "tracking", status: "ready"} = plan} -> gate_tracking_plan(plan)
      _other -> :ok
    end
  end

  def plan_changed(%PlanEvents.Changed{}), do: :ok

  defp gate_tracking_plan(plan) do
    found = plan.id |> Plans.units_for() |> Enum.count(&(&1.status == "found"))

    cond do
      found == 0 -> Plans.delete_tracking_draft(plan)
      tracking_mode(plan) == "ask" -> :ok
      tracking_mode(plan) == "off" -> discard(plan)
      true -> approve_or_discard(plan)
    end

    :ok
  end

  defp tracking_mode(plan) do
    case plan.tracking_item_id && ReleaseTracking.get_item(plan.tracking_item_id) do
      nil -> "off"
      item -> AutoGrabSettings.effective_mode(item.auto_grab_mode, AutoGrabSettings.load())
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

  defp discard(plan) do
    case Plans.discard(plan) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end
end
