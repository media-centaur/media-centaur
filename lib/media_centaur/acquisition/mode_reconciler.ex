defmodule MediaCentaur.Acquisition.ModeReconciler do
  @moduledoc """
  Mode-off mid-flight cleanup (ADR-056 Q11), run on the sweep tick
  before the drop planner: when an item's *effective* auto-grab mode is
  `off` — flipped per-item or inherited from a global default change —
  its automated in-flight artifacts are withdrawn.

  Tick-driven rather than flip-driven for the same reason the planner
  is (Q2, state-not-delta): one enforcement point sees per-item flips,
  global-default flips, and restarts identically, and self-heals if a
  pass is missed. Latency is bounded by the sweep cadence — the same
  laziness the legacy per-event policy had.

  What a pass withdraws, per legacy-policy parity:

  * **Parked tracking drafts** (`origin: "tracking"`, status `ready` —
    ask-mode plans awaiting approval) → discarded. Solving drafts are
    not touched here; the mode gate (`Reactor.Handlers.plan_changed/1`)
    already discards those when they finish solving.
  * **Still-seeking tracking pursuits** → system-cancelled with reason
    `auto_grab_disabled`. "Still seeking" means no acquired/succeeded
    target — the legacy policy's cancellable set was `searching/
    snoozed` only, so a live download is never killed by a mode flip
    (the user can cancel it on Downloads). Mixed pursuits with any
    landed/landing unit are conservatively left whole.

  What it never touches: `origin: "manual"` plan-now drafts and their
  pursuits (explicit user actions outrank the automation dial), wants
  (mode off ≠ stop wanting — media search remains the expected path,
  Q3, so system cancels leave the ledger open), and items that no
  longer exist (the `item_removed` Reactor path owns deletion).
  """

  import Ecto.Query

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.{AutoGrabSettings, CancelReasons, Plans, Target}
  alias MediaCentaur.Acquisition.Plans.Plan
  alias MediaCentaur.Acquisition.Pursuits.Commands.Cancel
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, State}
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Repo

  @doc "One reconciliation pass. Cheap when nothing is off — two small queries."
  @spec run_pass() :: :ok
  def run_pass do
    settings = AutoGrabSettings.load()

    _mode_cache =
      %{}
      |> then(&discard_parked_drafts(settings, &1))
      |> then(&cancel_seeking_pursuits(settings, &1))

    :ok
  end

  defp discard_parked_drafts(settings, off_items) do
    Plan
    |> where([p], p.origin == "tracking" and p.status == "ready")
    |> where([p], not is_nil(p.tracking_item_id))
    |> Repo.all()
    |> Enum.reduce(off_items, fn plan, cache ->
      {off?, cache} = off?(plan.tracking_item_id, settings, cache)

      if off? do
        case Plans.discard(plan) do
          {:ok, _discarded} ->
            Log.info(:acquisition, "tracking draft discarded (auto-grab off) — #{plan.title}")

          {:error, _reason} ->
            :ok
        end
      end

      cache
    end)
  end

  defp cancel_seeking_pursuits(settings, off_items) do
    Plan
    |> where([p], p.origin == "tracking")
    |> where([p], not is_nil(p.tracking_item_id) and not is_nil(p.pursuit_id))
    |> join(:inner, [p], pursuit in Pursuit, on: pursuit.id == p.pursuit_id)
    |> where([_p, pursuit], pursuit.state in ^State.in_flight())
    |> select([p, pursuit], {p.tracking_item_id, pursuit})
    |> Repo.all()
    |> Enum.reduce(off_items, fn {item_id, pursuit}, cache ->
      {off?, cache} = off?(item_id, settings, cache)

      if off? and still_seeking?(pursuit) do
        case Cancel.execute(%{
               pursuit_id: pursuit.id,
               cancelled_by: :system,
               reason: CancelReasons.auto_grab_disabled()
             }) do
          {:ok, _cancelled} ->
            Log.info(:acquisition, "tracking pursuit cancelled (auto-grab off) — #{pursuit.title}")

          {:error, _reason} ->
            :ok
        end
      end

      cache
    end)
  end

  # Legacy-policy parity: cancellable work is still-seeking work. Any
  # acquired/succeeded target means a download is (or was) live — leave
  # the pursuit alone.
  defp still_seeking?(%Pursuit{} = pursuit) do
    not (Target
         |> where([t], t.pursuit_id == ^pursuit.id and t.status in ["acquired", "succeeded"])
         |> Repo.exists?())
  end

  defp off?(item_id, settings, cache) do
    case cache do
      %{^item_id => off?} ->
        {off?, cache}

      _miss ->
        off? =
          case ReleaseTracking.get_item(item_id) do
            nil -> false
            item -> AutoGrabSettings.effective_mode(item.auto_grab_mode, settings) == "off"
          end

        {off?, Map.put(cache, item_id, off?)}
    end
  end
end
