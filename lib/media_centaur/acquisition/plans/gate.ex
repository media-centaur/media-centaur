defmodule MediaCentaur.Acquisition.Plans.Gate do
  @moduledoc """
  The approval gate (spec 2026-09-05; ADR-056 Q3 for the tracking rules):
  what happens to a plan when it finishes solving.

  A gated plan is owed this decision the moment it turns `ready`, so
  `Jobs.RunPlan` inserts `Jobs.GatePlan` in the same transaction as the
  transition (ADR-077, rule 1) and the job calls `run/1`. It used to ride
  a `PlanEvents.Changed` PubSub message to the Reactor; a lost message
  left an automatic plan waiting on the board, and a tracking draft
  blocking its want, for good.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Plans.Plan
  alias MediaCentaur.Discovery
  alias MediaCentaur.ReleaseTracking

  @doc """
  Decides a solved plan's fate from its stamped `approval_policy` —

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

  A plan that is no longer `ready` — discarded or committed while the
  gate waited — is left alone.
  """
  @spec run(Plan.t()) :: :ok
  def run(%Plan{status: "ready"} = plan), do: gate(plan)
  def run(%Plan{}), do: :ok

  @doc """
  Whether a plan is gated at all — a tracking draft, or a plan whose
  policy is `automatic`. A review plan waits for a person, so no gate is
  owed and `RunPlan` inserts no `Jobs.GatePlan` for it.
  """
  @spec needed?(Plan.t()) :: boolean()
  def needed?(%Plan{origin: "tracking"}), do: true
  def needed?(%Plan{approval_policy: "automatic"}), do: true
  def needed?(%Plan{}), do: false

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
