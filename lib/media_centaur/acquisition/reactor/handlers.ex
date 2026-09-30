defmodule MediaCentaur.Acquisition.Reactor.Handlers do
  @moduledoc """
  Translates release-tracking PubSub events into pursuit-orchestration
  side effects.

  Called by `Acquisition.Reactor` (the GenServer that owns the
  subscription). Splitting the handlers out of the Reactor keeps the
  GenServer module trivial — it's just a subscribe-and-dispatch shim —
  while keeping the drop-planner tick here in a testable plain-function
  module. The approval gate moved to `Plans.Gate`, run by
  `Jobs.GatePlan` (ADR-077).

  ## Public surface

  - `tracking_sweep_completed/0` — run the drop planner tick (ADR-056).
  - `prowlarr_available/0` — run the drop planner tick on Prowlarr's
    recovery.

  Pure dispatch + Acquisition-context side effects. No GenServer state.
  """

  alias MediaCentaur.Acquisition.{DropPlanner, ModeReconciler}

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
  Prowlarr answered again — plan the wants that came due while it was
  held, instead of waiting up to a sweep (15 minutes) for the next tick.
  Modes cannot have changed while Prowlarr was down, so this is the
  planner tick alone, not the full sweep pipeline.
  """
  @spec prowlarr_available() :: :ok
  def prowlarr_available, do: DropPlanner.run_tick()
end
